-- Use a package's manifest.xml file to find paths to the packages on
-- which this package is dependent.
module Ros.Build.DepFinder (findPackageDeps, buildDepMsgs) where
import Control.Applicative ((<$>))
import Control.Monad (when, filterM, (>=>))
import Data.Maybe (mapMaybe, isNothing, fromJust)
import Data.List (find, findIndex)
import System.Directory (doesFileExist, doesDirectoryExist, 
                         getDirectoryContents)
import System.Environment (getEnvironment)
import System.FilePath ((</>), splitSearchPath, takeExtension)
import System.Process (runCommand)
import Text.XML.Light

type Package = String

-- Find the path to a package based on the given search paths.
findPackagePath :: [FilePath] -> Package -> IO (Maybe FilePath)
findPackagePath search pkg = go search
    where go [] = return Nothing
          go (p:ps) = let pkgPath = p </> pkg
                      in do e <- doesDirectoryExist pkgPath
                            if e then return (Just pkgPath) else go ps

-- Get the packages listed as dependencies in an XML manifest.  NOTE:
-- In version 1.3.7, the xml package gained the ability to work with
-- ByteStrings via the XmlSource typeclass. Consider that upgrade if
-- performance is a consideration.
getPackages :: String -> Maybe [Package]
getPackages = (map attrVal . 
               mapMaybe (find ((==pkg).attrKey) . elAttribs) . 
               findChildren dep <$>) . 
              parseXMLDoc
    where pkg = QName "package" Nothing Nothing
          dep = QName "depend" Nothing Nothing

-- Directory listing returning the full path to each entry excluding
-- "."  and "..".
dir :: FilePath -> IO [FilePath]
dir p = getDirectoryContents p >>= return . map (p </>) . filter notDot
    where notDot s = s /= "." && s /= ".."

-- Each given path is a possible package path root, as are all of its
-- subdirectories that are stacks (indicated by the presence of a
-- stack.xml file).
packagePaths :: FilePath -> IO [FilePath]
packagePaths path = (path :) <$> (filterM isStack =<< dir path)
    where isStack = doesFileExist . (</> "stack.xml")

-- Get every package directory on the ROS search path.
getRosPaths :: IO [FilePath]
getRosPaths = 
    do env <- getEnvironment
       let pPaths = case lookup "ROS_PACKAGE_PATH" env of
                      Just s -> s
                      Nothing -> error "ROS_PACKAGE_PATH not set in environment"
           rPath = case lookup "ROS_ROOT" env of
                     Just s -> s
                     Nothing -> error "ROS_ROOT not set in environment"
           allPaths = rPath : (rPath</>"core") : splitSearchPath pPaths
       concat <$> (mapM packagePaths =<< filterM doesDirectoryExist allPaths)

-- |Find the paths to the packages this package depends on as
-- indicated by the manifest.xml file in this package's root
-- directory.
findPackageDeps :: FilePath -> IO [FilePath]
findPackageDeps pkgRoot = 
    let man = pkgRoot </> "manifest.xml"
    in do exists <- doesFileExist man
          when (not exists)
               (error "Couldn't find manifest.xml")
          txt <- readFile man
          let pkgs = case getPackages txt of
                       Nothing -> error "Couldn't parse manifest.xml"
                       Just pkgs -> pkgs
          searchPaths <- getRosPaths
          -- Add an implicit dependency on the "roslib" package.
          pkgPaths <- mapM (findPackagePath searchPaths) ("roslib":pkgs)
          case findIndex isNothing pkgPaths of
            Just i -> error $ "Couldn't find path to package " ++ (pkgs !! i)
            Nothing -> return $ map fromJust pkgPaths

-- Return the full path to every .msg file in the given package
-- directory.
findMessages :: FilePath -> IO [FilePath]
findMessages path = aux =<< doesDirectoryExist msgPath
    where msgPath = path </> "msg"
          aux True = return . filter isMsg =<< dir msgPath
          aux False = return []
          isMsg = (==".msg") . takeExtension

-- |Run "roshask gen" on all the .msg files in each of the given
-- package directories.
buildDepMsgs :: [FilePath] -> IO ()
buildDepMsgs = mapM_ (findMessages >=> 
                      mapM_ (cmd . ("roshask gen "++)))
    where cmd = runCommand >=> \_ -> return ()

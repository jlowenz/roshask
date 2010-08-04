{-# LANGUAGE ScopedTypeVariables #-}
module Ros.Util.BytesToVector (bytesToVector, bytesToVectorL, bytesToVectorCopy,
                               vectorToBytes, vectorToBytesCopy) where
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as BS
import qualified Data.ByteString.Unsafe as BU
import qualified Data.Vector.Storable as V
import Foreign.Ptr (castPtr, plusPtr)
import Foreign.ForeignPtr (newForeignPtr_, withForeignPtr, 
                           mallocForeignPtrBytes)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Storable (sizeOf)
import System.IO.Unsafe (unsafePerformIO)

-- |Construct a 'V.Vector' with the specified number of elements from
-- a strict 'BS.ByteString' without copying.
bytesToVector :: V.Storable a => Int -> BS.ByteString -> V.Vector a
bytesToVector n bs = unsafePerformIO $
                     BU.unsafeUseAsCStringLen bs $
                     (\(p,_) -> do fp <- newForeignPtr_ (castPtr p)
                                   return $ V.unsafeFromForeignPtr fp 0 n)

-- |Construct a 'V.Vector' with the specified number of elements from
-- a strict 'BS.ByteString' making a copy of the underlying data in
-- the process.
bytesToVectorCopy :: V.Storable a => Int -> BS.ByteString -> V.Vector a
bytesToVectorCopy n bs = unsafePerformIO $
                         BU.unsafeUseAsCStringLen bs $
                         (\(p,len) -> do fp <- mallocForeignPtrBytes len
                                         withForeignPtr fp $
                                           \dst -> copyBytes (castPtr dst) p len
                                         return $ V.unsafeFromForeignPtr fp 0 n)


-- |Construct a 'V.Vector' with the specified number of elements from
-- a lazy 'BL.ByteString'.
bytesToVectorL :: V.Storable a => Int -> BL.ByteString -> V.Vector a
bytesToVectorL n = bytesToVector n . BS.concat . BL.toChunks

-- |Construct a strict 'BS.ByteString' from a 'V.Vector' without
-- copying the underlying data.
vectorToBytes :: forall a. V.Storable a => V.Vector a -> BS.ByteString
vectorToBytes v = 
    unsafePerformIO $
    withForeignPtr fp (\p -> let p' = castPtr $ plusPtr p offset
                             in BU.unsafePackCStringLen (p', len*sz))
    where (fp,offset,len) = V.unsafeToForeignPtr v
          sz = sizeOf (undefined::a)

-- |Construct a strict 'BS.ByteString' from a 'V.Vector'. This
-- involves copying the underlying bytes.
vectorToBytesCopy :: forall a. V.Storable a => V.Vector a-> BS.ByteString
vectorToBytesCopy v = 
    unsafePerformIO $
    withForeignPtr fp (\p -> let p' = castPtr $ plusPtr p offset
                             in BS.packCStringLen (p', len*sz))
    where (fp,offset,len) = V.unsafeToForeignPtr v
          sz = sizeOf (undefined::a)



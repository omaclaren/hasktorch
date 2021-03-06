{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ForeignFunctionInterface#-}

module Torch.Core.Tensor.Dynamic.Long
  ( tl_get
  , tl_new
  ) where

import Foreign
import Foreign.C.Types
import Foreign.Ptr
import Foreign.ForeignPtr( ForeignPtr, withForeignPtr, mallocForeignPtrArray,
                           newForeignPtr )
import GHC.Ptr (FunPtr)
import Numeric (showGFloat)
import System.IO.Unsafe (unsafePerformIO)

import Torch.Core.Internal (w2cll)
import Torch.Core.Tensor.Raw hiding (fillRaw, fillRaw0)
import Torch.Core.Tensor.Types
import THTypes
import THLongTensor
import THLongTensorMath
import THLongLapack

wrapLong tensor = TensorLong <$> (newForeignPtr p_THLongTensor_free tensor)

tl_get loc tensor =
   (withForeignPtr(tlTensor tensor) (\t ->
                                        pure $ getter loc t
                                    ))
  where
    getter D0 t = undefined
    getter (D1 d1) t = c_THLongTensor_get1d t $ w2cll d1
    getter (D2 (d1, d2)) t = c_THLongTensor_get2d t
                          (w2cll d1) (w2cll d2)
    getter (D3 (d1, d2, d3)) t = c_THLongTensor_get3d t
                             (w2cll d1) (w2cll d2) (w2cll d3)
    getter (D4 (d1, d2, d3, d4)) t = c_THLongTensor_get4d t
                                (w2cll d1) (w2cll d2) (w2cll d3) (w2cll d4)


-- |Returns a function that accepts a tensor and fills it with specified value
-- and returns the IO context with the mutated tensor
-- fillRaw :: Real a => a -> TensorLongRaw -> IO ()
fillRaw value = (flip c_THLongTensor_fill) (fromIntegral value)

-- |Fill a raw Long tensor with 0.0
fillRaw0 :: TensorLongRaw -> IO (TensorLongRaw)
fillRaw0 tensor = fillRaw 0 tensor >> pure tensor


-- |Create a new (Long) tensor of specified dimensions and fill it with 0
tl_new :: TensorDim Word -> TensorLong
tl_new dims = unsafePerformIO $ do
  newPtr <- go dims
  fPtr <- newForeignPtr p_THLongTensor_free newPtr
  withForeignPtr fPtr fillRaw0
  pure $ TensorLong fPtr dims
  where
    wrap ptr = newForeignPtr p_THLongTensor_free ptr
    go D0 = c_THLongTensor_new
    go (D1 d1) = c_THLongTensor_newWithSize1d $ w2cll d1
    go (D2 (d1, d2)) = c_THLongTensor_newWithSize2d
                    (w2cll d1) (w2cll d2)
    go (D3 (d1, d2, d3)) = c_THLongTensor_newWithSize3d
                       (w2cll d1) (w2cll d2) (w2cll d3)
    go (D4 (d1, d2, d3, d4)) = c_THLongTensor_newWithSize4d
                          (w2cll d1) (w2cll d2) (w2cll d3) (w2cll d4)

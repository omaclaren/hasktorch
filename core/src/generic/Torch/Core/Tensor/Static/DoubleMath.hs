{-# OPTIONS_GHC -fno-cse -fno-full-laziness #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module Torch.Core.Tensor.Static.DoubleMath
  ( (^+^)
  , (^-^)
  , (^*^)
  , (^/^)
  , (!*)
  , (!*!)
  , (^+)
  , (^-)
  , (+^)
  , (-^)
  , (^*)
  , (^/)
  , (*^)
  , (/^)
  , (<.>)

  , tds_fill
  , tds_fill_

  , tds_addConst
  , tds_subConst
  , tds_mulConst
  , tds_divConst

  , tds_dot

  , tds_minAll
  , tds_maxAll
  , tds_medianAll
  , tds_sumAll
  , tds_prodAll
  , tds_meanAll

  , tds_neg
  , tds_cinv
  , tds_ltTensorT
  , tds_leTensorT
  , tds_gtTensorT
  , tds_geTensorT
  , tds_neTensorT
  , tds_eqTensorT
  , tds_abs

  , tds_sigmoid
  , tds_log
  , tds_lgamma
  , tds_log1p
  , tds_exp
  , tds_acos
  , tds_cosh
  , tds_sin
  , tds_asin
  , tds_sinh
  , tds_tan
  , tds_atan
  -- , tds_atan2
  , tds_tanh
  , tds_pow
  , tds_tpow
  , tds_sqrt
  , tds_rsqrt
  , tds_ceil
  , tds_floor
  , tds_round

  , tds_cadd
  , tds_csub
  , tds_cmul
  , tds_square
  , tds_cpow
  , tds_cdiv
  , tds_clshift
  , tds_crshift
  , tds_cfmod
  , tds_cremainder
  , tds_cbitand
  , tds_cbitor
  , tds_cbitxor
  -- , tds_addcmul
  -- , tds_addcdiv
  , tds_addmv
  , tds_mv

  , tds_addmm
  , tds_addr
  , tds_outer
  , tds_addbmm
  , tds_baddbmm
  , tds_match
  , tds_numel
  , tds_max
  , tds_min
  , tds_kthvalue
  , tds_mode
  , tds_median
  , tds_sum
  , tds_colsum
  , tds_rowsum
  , tds_prod
  , tds_cumsum
  , tds_cumprod
  , tds_sign
  , tds_trace
  , tds_cross

  , tds_equal

  , tds_cat
  , tds_diag

  ) where

import Control.Monad.Managed
import Data.Singletons
import Data.Singletons.TypeLits
import Data.Singletons.Prelude.List
import Foreign (Ptr)
import Foreign.C.Types (CLong, CDouble, CInt)
import Foreign.ForeignPtr ( ForeignPtr, withForeignPtr, newForeignPtr )
import System.IO.Unsafe (unsafePerformIO)

import Torch.Core.Tensor.Raw
import Torch.Core.Tensor.Types
import Torch.Core.Tensor.Dynamic.Double
import Torch.Core.Tensor.Dynamic.Long
import THTypes
import THDoubleTensor
import THDoubleTensorMath
import Torch.Core.Tensor.Static.Double

{- Operators -}

-- |Experimental num instance for static tensors
instance SingI d => Num (TensorDoubleStatic d) where
  (+) t1 t2 = tds_cadd t1 1.0 t2
  (-) t1 t2 = tds_csub t1 1.0  t2
  (*) t1 t2 = tds_cmul t1 t2
  abs t = tds_abs t
  signum t = error "signum not defined for tensors"
  fromInteger t = error "signum not defined for tensors"

(!*) :: (KnownNat c, KnownNat r) => (TDS '[r, c]) -> (TDS '[c]) -> (TDS '[r])
(!*) m v = tds_mv m v

(!*!) :: (KnownNat a, KnownNat b, KnownNat c) =>
  TDS '[a, b] -> TDS '[b, c] -> TDS '[a,c]
(!*!) m1 m2 = tds_addmm 1.0 tds_new 1.0 m1 m2

(^+^) t1 t2 = tds_cadd t1 1.0 t2
(^-^) t1 t2 = tds_csub t1 1.0 t2
(^*^) t1 t2 = tds_cmul t1 t2
(^/^) t1 t2 = tds_cdiv t1 t2

(^+) :: (Real p, SingI d) => TDS d -> p -> TDS d
(^+) = tds_addConst

(^-) :: (Real p, SingI d) => TDS d -> p -> TDS d
(^-) = tds_subConst

(^*) :: (SingI d, Real p) => TDS d -> p -> TDS d
(^*) = tds_mulConst

(^/) :: (SingI d, Real p) => TDS d -> p -> TDS d
(^/) = tds_divConst

(+^) :: (Real p, SingI d) => p -> TDS d -> TDS d
(+^) = flip tds_addConst

(-^) :: (Real p, SingI d) => p -> TDS d -> TDS d
(-^) val t = tds_addConst (tds_neg t) val

(*^) :: (SingI d, Real p) => p -> TDS d -> TDS d
(*^) = flip tds_mulConst

(/^) :: (SingI d, Real p) => p -> TDS d -> TDS d
(/^) val t = tds_mulConst (tds_cinv t) val

(<.>) t1 t2 = tds_dot t1 t2

{- Helper functions -}

-- |Generalize non-mutating collapse of a tensor to a constant or another tensor
apply0_ :: (Ptr CTHDoubleTensor -> a) -> (TDS d) -> IO a
apply0_ operation tensor = do
  withForeignPtr (tdsTensor tensor) (\t -> pure $ operation t)

apply1_ :: SingI d => (Ptr CTHDoubleTensor -> Ptr CTHDoubleTensor -> IO a)
     -> (TDS d) -> p -> (TDS d)
apply1_ transformation mtx val = unsafePerformIO $ do
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor res)
    tPtr <- managed $ withForeignPtr (tdsTensor mtx)
    liftIO $ transformation rPtr tPtr
    liftIO (pure ())
  pure res
  where
    res = tds_cloneDim mtx
{-# NOINLINE apply1_ #-}

tds_fill :: (Real a, SingI d) => a -> p -> TensorDoubleStatic d
tds_fill value tensor = unsafePerformIO $
  withForeignPtr (tdsTensor nt) (\t -> do
                                  fillRaw value t
                                  pure nt
                              )
  where nt = tds_new
{-# NOINLINE tds_fill #-}

tds_fill_ :: Real a => a -> (TDS d) -> IO ()
tds_fill_ value tensor =
  withForeignPtr(tdsTensor tensor) (\t -> fillRaw value t)

tds_addConst :: (SingI d, Real p) => TDS d -> p -> TDS d
tds_addConst mtx val = apply1_ tAdd mtx val
  where
    tAdd r_ t = c_THDoubleTensor_add r_ t (realToFrac val)

tds_subConst :: (SingI d, Real p) => TDS d -> p -> TDS d
tds_subConst mtx val = apply1_ tSub mtx val
  where
    tSub r_ t = c_THDoubleTensor_sub r_ t (realToFrac val)

tds_mulConst :: (SingI d, Real p) => TDS d -> p -> TDS d
tds_mulConst mtx val = apply1_ tMul mtx val
  where
    tMul r_ t = c_THDoubleTensor_mul r_ t (realToFrac val)

tds_divConst :: (SingI d, Real p) => TDS d -> p -> TDS d
tds_divConst mtx val = apply1_ tDiv mtx val
  where
    tDiv r_ t = c_THDoubleTensor_div r_ t (realToFrac val)

tds_dot :: (TDS d) -> (TDS d) -> Double
tds_dot t src = realToFrac $ unsafePerformIO $ do
  with (do
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    srcPtr <- managed $ withForeignPtr (tdsTensor src)
    pure (tPtr, srcPtr))
    (\(tPtr, srcPtr) -> pure $ c_THDoubleTensor_dot tPtr srcPtr)
{-# NOINLINE tds_dot #-}

tds_minAll :: (TDS d) -> Double
tds_minAll tensor = unsafePerformIO $ apply0_ tMinAll tensor
  where
    tMinAll t = realToFrac $ c_THDoubleTensor_minall t
{-# NOINLINE tds_minAll #-}

tds_maxAll :: (TDS d) -> Double
tds_maxAll tensor = unsafePerformIO $ apply0_ tMaxAll tensor
  where
    tMaxAll t = realToFrac $ c_THDoubleTensor_maxall t
{-# NOINLINE tds_maxAll #-}

tds_medianAll :: (TDS d) -> Double
tds_medianAll tensor = unsafePerformIO $ apply0_ tMedianAll tensor
  where
    tMedianAll t = realToFrac $ c_THDoubleTensor_medianall t
{-# NOINLINE tds_medianAll #-}

tds_sumAll :: (TDS d) -> Double
tds_sumAll tensor = unsafePerformIO $ apply0_ tSumAll tensor
  where
    tSumAll t = realToFrac $ c_THDoubleTensor_sumall t
{-# NOINLINE tds_sumAll #-}

tds_prodAll :: (TDS d) -> Double
tds_prodAll tensor = unsafePerformIO $ apply0_ tProdAll tensor
  where
    tProdAll t = realToFrac $ c_THDoubleTensor_prodall t
{-# NOINLINE tds_prodAll #-}

tds_meanAll :: (TDS d) -> Double
tds_meanAll tensor = unsafePerformIO $ apply0_ tMeanAll tensor
  where
    tMeanAll t = realToFrac $ c_THDoubleTensor_meanall t
{-# NOINLINE tds_meanAll #-}

-- ----------------------------------------
-- Tensor to Tensor transformation
-- ----------------------------------------

-- |Wrapper to apply tensor -> tensor non-mutating operation
apply0Tensor
  :: SingI d => (Ptr CTHDoubleTensor -> t -> IO a) -> t -> (TDS d)
apply0Tensor op t = unsafePerformIO $ do
  let res = tds_new
  withForeignPtr (tdsTensor res) (\r_ -> op r_ t)
  pure res
{-# NOINLINE apply0Tensor #-}

-- |Returns a tensor with values negated
tds_neg :: SingI d => TDS d -> TDS d
tds_neg tensor = unsafePerformIO $ apply0_ tNeg tensor
  where
    tNeg t = apply0Tensor c_THDoubleTensor_neg t
{-# NOINLINE tds_neg #-}

tds_cinv :: SingI d => TDS d -> TDS d
tds_cinv tensor = unsafePerformIO $ apply0_ tInv tensor
  where
    tInv t = apply0Tensor c_THDoubleTensor_cinv t
{-# NOINLINE tds_cinv #-}

-- ----------------------------------------
-- Tensor vs. tensor comparison, retaining double type
-- ----------------------------------------

-- |Returns a tensor of 0.0 and 1.0 by comparing whether ta < tb for each value
tds_ltTensorT :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_ltTensorT ta tb = unsafePerformIO $
  apply2 c_THDoubleTensor_ltTensorT ta tb
{-# NOINLINE tds_ltTensorT #-}

-- |Returns a tensor of 0.0 and 1.0 by comparing whether ta <= tb for each value
tds_leTensorT :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_leTensorT ta tb = unsafePerformIO $
  apply2 c_THDoubleTensor_leTensorT ta tb
{-# NOINLINE tds_leTensorT #-}

-- |Returns a tensor of 0.0 and 1.0 by comparing whether ta > tb for each value
tds_gtTensorT :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_gtTensorT ta tb = unsafePerformIO $
  apply2 c_THDoubleTensor_gtTensorT ta tb
{-# NOINLINE tds_gtTensorT #-}

-- |Returns a tensor of 0.0 and 1.0 by comparing whether ta >= tb for each value
tds_geTensorT :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_geTensorT ta tb = unsafePerformIO $
  apply2 c_THDoubleTensor_geTensorT ta tb
{-# NOINLINE tds_geTensorT #-}

-- |Returns a tensor of 0.0 and 1.0 by comparing whether ta /= tb for each value
tds_neTensorT :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_neTensorT ta tb = unsafePerformIO $
  apply2 c_THDoubleTensor_neTensorT ta tb
{-# NOINLINE tds_neTensorT #-}

-- |Returns a tensor of 0.0 and 1.0 by comparing whether ta == tb for each value
tds_eqTensorT :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_eqTensorT ta tb = unsafePerformIO $
  apply2 c_THDoubleTensor_eqTensorT ta tb
{-# NOINLINE tds_eqTensorT #-}

-- ----------------------------------------
-- Additional transformations
-- ----------------------------------------

-- |Returns a tensor where each value of the input tensor is transformed as its
-- absolute value
tds_abs :: SingI d => TDS d -> TDS d
tds_abs t = unsafePerformIO $ apply0_ tAbs t
  where
    tAbs t' = apply0Tensor c_THDoubleTensor_abs t'
{-# NOINLINE tds_abs #-}

-- |Returns a t where each value of the input tensor is transformed as the
-- sigmoid of the value
tds_sigmoid :: SingI d => TDS d -> TDS d
tds_sigmoid t = unsafePerformIO $ apply0_ tSigmoid t
  where
    tSigmoid t' = apply0Tensor c_THDoubleTensor_sigmoid t'
{-# NOINLINE tds_sigmoid #-}

-- |Returns a tensor where each value of the input tensor is transformed as the
-- log of the value
tds_log :: SingI d => TDS d -> TDS d
tds_log t = unsafePerformIO $ apply0_ tLog t
  where
    tLog t' = apply0Tensor c_THDoubleTensor_log t'
{-# NOINLINE tds_log #-}

-- |Returns a tensor where each value of the input tensor is transformed as the
-- log gamma of the value
tds_lgamma :: SingI d => TDS d -> TDS d
tds_lgamma t = unsafePerformIO $ apply0_ tLgamma t
  where
    tLgamma t' = apply0Tensor c_THDoubleTensor_lgamma t'
{-# NOINLINE tds_lgamma #-}

-- |Returns a new tensor with the natural log of 1 + the elements
tds_log1p :: SingI d => TDS d -> TDS d
tds_log1p t = unsafePerformIO $ apply0_ tLog1p t
  where
    tLog1p t' = apply0Tensor c_THDoubleTensor_log1p t'
{-# NOINLINE tds_log1p #-}

-- |Returns a tensor where each value of the input tensor is transformed as the
-- exp of the value
tds_exp :: SingI d => TDS d -> TDS d
tds_exp t = unsafePerformIO $ apply0_ tExp t
  where
    tExp t' = apply0Tensor c_THDoubleTensor_exp t'
{-# NOINLINE tds_exp #-}

tds_cos :: SingI d => TDS d -> TDS d
tds_cos t = unsafePerformIO $ apply0_ tCos t
  where
    tCos t' = apply0Tensor c_THDoubleTensor_cos t'
{-# NOINLINE tds_cos #-}

tds_acos :: SingI d => TDS d -> TDS d
tds_acos t = unsafePerformIO $ apply0_ tAcos t
  where
    tAcos t' = apply0Tensor c_THDoubleTensor_acos t'
{-# NOINLINE tds_acos #-}

tds_cosh :: SingI d => TDS d -> TDS d
tds_cosh t = unsafePerformIO $ apply0_ tCosh t
  where
    tCosh t' = apply0Tensor c_THDoubleTensor_cosh t'
{-# NOINLINE tds_cosh #-}

tds_sin :: SingI d => TDS d -> TDS d
tds_sin t = unsafePerformIO $ apply0_ tSin t
  where
    tSin t' = apply0Tensor c_THDoubleTensor_sin t'
{-# NOINLINE tds_sin #-}

tds_asin :: SingI d => TDS d -> TDS d
tds_asin t = unsafePerformIO $ apply0_ tAsin t
  where
    tAsin t' = apply0Tensor c_THDoubleTensor_asin t'
{-# NOINLINE tds_asin #-}

tds_sinh :: SingI d => TDS d -> TDS d
tds_sinh t = unsafePerformIO $ apply0_ tSinh t
  where
    tSinh t' = apply0Tensor c_THDoubleTensor_sinh t'
{-# NOINLINE tds_sinh #-}

tds_tan :: SingI d => TDS d -> TDS d
tds_tan t = unsafePerformIO $ apply0_ tTan t
  where
    tTan t' = apply0Tensor c_THDoubleTensor_tan t'
{-# NOINLINE tds_tan #-}

tds_atan :: SingI d => TDS d -> TDS d
tds_atan t = unsafePerformIO $ apply0_ tAtan t
  where
    tAtan t' = apply0Tensor c_THDoubleTensor_atan t'
{-# NOINLINE tds_atan #-}

tds_tanh :: SingI d => TDS d -> TDS d
tds_tanh t = unsafePerformIO $ apply0_ tTanh t
  where
    tTanh t' = apply0Tensor c_THDoubleTensor_tanh t'
{-# NOINLINE tds_tanh #-}

tds_pow :: SingI d => TDS d -> Double -> TDS d
tds_pow t value = unsafePerformIO $ do
  let res = tds_new
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor res)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    liftIO $ c_THDoubleTensor_pow rPtr tPtr valueC
  pure res
  where
    valueC = realToFrac value
{-# NOINLINE tds_pow #-}

tds_tpow :: SingI d => Double -> TDS d -> TDS d
tds_tpow value t = unsafePerformIO $ do
  let res = tds_new
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor res)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    liftIO $ c_THDoubleTensor_tpow rPtr valueC tPtr
  pure res
  where
    valueC = realToFrac value
{-# NOINLINE tds_tpow #-}

tds_sqrt :: SingI d => TDS d -> TDS d
tds_sqrt t = unsafePerformIO $ apply0_ tSqrt t
  where
    tSqrt t' = apply0Tensor c_THDoubleTensor_sqrt t'
{-# NOINLINE tds_sqrt #-}

tds_rsqrt :: SingI d => TDS d -> TDS d
tds_rsqrt t = unsafePerformIO $ apply0_ tRsqrt t
  where
    tRsqrt t' = apply0Tensor c_THDoubleTensor_rsqrt t'
{-# NOINLINE tds_rsqrt #-}

tds_ceil :: SingI d => TDS d -> TDS d
tds_ceil t = unsafePerformIO $ apply0_ tCeil t
  where
    tCeil t' = apply0Tensor c_THDoubleTensor_ceil t'
{-# NOINLINE tds_ceil #-}

tds_floor :: SingI d => TDS d -> TDS d
tds_floor t = unsafePerformIO $ apply0_ tFloor t
  where
    tFloor t' = apply0Tensor c_THDoubleTensor_floor t'
{-# NOINLINE tds_floor #-}

tds_round :: SingI d => TDS d -> TDS d
tds_round t = unsafePerformIO $ apply0_ tRound t
  where
    tRound t' = apply0Tensor c_THDoubleTensor_round t'
{-# NOINLINE tds_round #-}


-- ----------------------------------------
-- c* cadd, cmul, cdiv, cpow, ...
-- ----------------------------------------

-- usually this is 1 mutation arg + 2 parameter args
type Raw3Arg = Ptr CTHDoubleTensor -> Ptr CTHDoubleTensor -> Ptr CTHDoubleTensor -> IO ()

-- usually this is 1 mutation arg + 3 parameter args
type Raw4Arg = Ptr CTHDoubleTensor -> Ptr CTHDoubleTensor ->Ptr CTHDoubleTensor -> Ptr CTHDoubleTensor -> IO ()

apply2 :: (SingI d1, SingI d2, SingI d3) =>
  Raw3Arg -> (TDS d1) -> (TDS d2) -> IO (TDS d3)
apply2 fun t src = do
  let r_ = tds_new
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor r_)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    srcPtr <- managed $ withForeignPtr (tdsTensor src)
    liftIO $ fun rPtr tPtr srcPtr
  pure r_

apply3 :: (SingI d1, SingI d2, SingI d3, SingI d4) =>
  Raw4Arg -> (TDS d1) -> (TDS d2) -> (TDS d3) -> IO (TDS d4)
apply3 fun t src1 src2 = do
  let r_ = tds_new
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor r_)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    src1Ptr <- managed $ withForeignPtr (tdsTensor src1)
    src2Ptr <- managed $ withForeignPtr (tdsTensor src2)
    liftIO $ fun rPtr tPtr src1Ptr src2Ptr
  pure r_

-- argument rotations - used so that the constants are curried and only tensor
-- pointers are needed for apply* functions
-- mnemonic for reasoning about the type signature - "where did the argument end up" defines the new ordering
swap1
  :: (t1 -> t2 -> t3 -> t4 -> t5) -> t3 -> t1 -> t2 -> t4 -> t5
swap1 fun a b c d = fun b c a d
-- a is applied at position 3, type 3 is arg1
-- b is applied at position 1, type 1 is arg2
-- c is applied at position 2, type 2 is arg3
-- d is applied at position 4, type 4 is arg 4

swap2 fun a b c d e = fun b c a d e

swap3 fun a b c d e f = fun c a d b e f

-- cadd = z <- y + scalar * x, z value discarded
tds_cadd :: SingI d => (TDS d) -> Double -> (TDS d) -> (TDS d)
tds_cadd t scale src = unsafePerformIO $
  apply2 ((swap1 c_THDoubleTensor_cadd) scaleC) t src
  where scaleC = realToFrac scale
{-# NOINLINE tds_cadd #-}

tds_csub :: SingI d => (TDS d) -> Double -> (TDS d) -> (TDS d)
tds_csub t scale src = unsafePerformIO $ do
  apply2 ((swap1 c_THDoubleTensor_csub) scaleC) t src
  where scaleC = realToFrac scale
{-# NOINLINE tds_csub #-}

tds_cmul :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cmul t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cmul t src
{-# NOINLINE tds_cmul #-}

tds_square :: SingI d => TDS d -> TDS d
tds_square t = tds_cmul t t

tds_cpow :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cpow t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cpow t src
{-# NOINLINE tds_cpow #-}

tds_cdiv :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cdiv t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cdiv t src
{-# NOINLINE tds_cdiv #-}

tds_clshift :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_clshift t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_clshift t src
{-# NOINLINE tds_clshift #-}

tds_crshift :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_crshift t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_crshift t src
{-# NOINLINE tds_crshift #-}

tds_cfmod :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cfmod t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cfmod t src
{-# NOINLINE tds_cfmod #-}

tds_cremainder :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cremainder t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cremainder t src
{-# NOINLINE tds_cremainder #-}

tds_cbitand :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cbitand  t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cbitand t src
{-# NOINLINE tds_cbitand #-}

tds_cbitor :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cbitor  t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cbitor t src
{-# NOINLINE tds_cbitor #-}

tds_cbitxor :: SingI d => (TDS d) -> (TDS d) -> (TDS d)
tds_cbitxor t src = unsafePerformIO $ do
  apply2 c_THDoubleTensor_cbitxor t src
{-# NOINLINE tds_cbitxor #-}

-- TODO - fix constraints on type signatures for addcmul and addcdiv

-- tds_addcmul :: SingI d => (TDS d) -> Double -> (TDS d) -> (TDS d) -> (TDS d)
-- tds_addcmul t scale src1 src2 = unsafePerformIO $ do
--   apply3 ((swap2 c_THDoubleTensor_addcmul) scaleC) t src1 src2
--   where scaleC = (realToFrac scale) :: CDouble

-- tds_addcdiv :: SingI d => (TDS d) -> Double -> (TDS d) -> (TDS d) -> (TDS d)
-- tds_addcdiv t scale src1 src2 = unsafePerformIO $ do
--   apply3 ((swap2 c_THDoubleTensor_addcdiv) scaleC) t src1 src2
--   where scaleC = (realToFrac scale) :: CDouble

-- |beta * t + alpha * (src1 #> src2)
tds_addmv :: (KnownNat c, KnownNat r) =>
  Double -> (TDS '[r]) -> Double -> (TDS '[r, c]) -> (TDS '[c]) -> (TDS '[r])
tds_addmv beta t alpha src1 src2 = unsafePerformIO $ do
  apply3 ((swap3 c_THDoubleTensor_addmv) betaC alphaC) t src1 src2
  where
    (betaC, alphaC) = (realToFrac beta, realToFrac alpha) :: (CDouble, CDouble)
{-# NOINLINE tds_addmv #-}

-- | added simplified use of addmv: src1 #> src2
tds_mv :: (KnownNat c, KnownNat r) => (TDS '[r, c]) -> (TDS '[c]) -> (TDS '[r])
tds_mv m v = tds_addmv 0.0 tds_new 1.0 m v

apply1 fun t = do
  let r_ = tds_new
  withForeignPtr (tdsTensor r_)
    (\rPtr ->
       withForeignPtr (tdsTensor t)
         (\tPtr ->
            fun rPtr tPtr
         )
    )
  pure r_

type Ret2Fun =
  Ptr CTHDoubleTensor -> Ptr CTHLongTensor -> Ptr CTHDoubleTensor -> CInt -> CInt -> IO ()

ret2 :: SingI d => Ret2Fun -> (TDS d) -> Int -> Bool -> IO ((TDS d), TensorLong)
ret2 fun t dimension keepdim = do
  let values_ = tds_new
  let indices_ = tl_new (tds_dim t)
  runManaged $ do
    vPtr <- managed $ withForeignPtr (tdsTensor values_)
    iPtr <- managed $ withForeignPtr (tlTensor indices_)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    liftIO $ fun vPtr iPtr tPtr dimensionC keepdimC
  pure (values_, indices_)
  where
    keepdimC = if keepdim then 1 else 0
    dimensionC = fromIntegral dimension

tds_addmm :: (KnownNat a, KnownNat b, KnownNat c) =>
  Double -> TDS [a,c] -> Double -> TDS [a, b] -> TDS [b, c] -> TDS [a,c]
tds_addmm beta t alpha src1 src2 = unsafePerformIO $ do
  apply3 ((swap3 c_THDoubleTensor_addmm) betaC alphaC) t src1 src2
  where
    (betaC, alphaC) = (realToFrac beta, realToFrac alpha) :: (CDouble, CDouble)
{-# NOINLINE tds_addmm #-}

tds_addr :: (KnownNat r, KnownNat c) =>
  Double -> TDS '[r, c]-> Double -> TDS '[r] -> TDS '[c]-> TDS '[r, c]
tds_addr beta t alpha vec1 vec2 = unsafePerformIO $ do
  let r_ = tds_new
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor r_)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    vec1Ptr <- managed $ withForeignPtr (tdsTensor vec1)
    vec2Ptr <- managed $ withForeignPtr (tdsTensor vec2)
    liftIO $ c_THDoubleTensor_addr rPtr betaC tPtr alphaC vec1Ptr vec2Ptr
  pure r_
  where
    (betaC, alphaC) = (realToFrac beta, realToFrac alpha) :: (CDouble, CDouble)
{-# NOINLINE tds_addr #-}

tds_outer :: (KnownNat r, KnownNat c) =>
             TDS '[r] -> TDS '[c] -> TDS '[r, c]
tds_outer vec1 vec2 = tds_addr 0.0 tds_new 1.0 vec1 vec2

-- TODO- add proper type signature with dimensions specified
-- tds_addbmm :: Double -> (TDS d) -> Double -> (TDS d) -> (TDS d) -> (TDS d)
tds_addbmm beta t alpha batch1 batch2 = unsafePerformIO $ do
  apply3 ((swap3 c_THDoubleTensor_addbmm) betaC alphaC) t batch1 batch2
  where
    (betaC, alphaC) = (realToFrac beta, realToFrac alpha) :: (CDouble, CDouble)
{-# NOINLINE tds_addbmm #-}

-- TODO- add proper type signature with dimensions specified
-- tds_baddbmm :: Double -> (TDS d) -> Double -> (TDS d) -> (TDS d) -> (TDS d)
tds_baddbmm beta t alpha batch1 batch2 = unsafePerformIO $ do
  apply3 ((swap3 c_THDoubleTensor_baddbmm) betaC alphaC) t batch1 batch2
  where
    (betaC, alphaC) = (realToFrac beta, realToFrac alpha) :: (CDouble, CDouble)
{-# NOINLINE tds_baddbmm #-}

-- tds_match :: (TDS d) -> (TDS d) -> Double -> (TDS d)
tds_match m1 m2 gain = unsafePerformIO $ do
  apply2 ((swap c_THDoubleTensor_match) gainC) m1 m2
  where
    gainC = realToFrac gain
    swap fun gain b c d = fun b c d gain
{-# NOINLINE tds_match #-}

tds_numel :: (TDS d) -> Int
tds_numel t = unsafePerformIO $ do
  result <- apply0_ c_THDoubleTensor_numel t
  pure $ fromIntegral result
{-# NOINLINE tds_numel #-}

{-
TODO : need type computations for resulting dimensions
-}

-- TH_API void THTensor_(max)(THTensor *values_, THLongTensor *indices_, THTensor *t, int dimension, int keepdim);
tds_max :: SingI d => (TDS d) -> Int -> Bool -> ((TDS d), TensorLong)
tds_max t dimension keepdim = unsafePerformIO $
  ret2 c_THDoubleTensor_max t dimension keepdim
{-# NOINLINE tds_max #-}

-- TH_API void THTensor_(min)(THTensor *values_, THLongTensor *indices_, THTensor *t, int dimension, int keepdim);
-- tds_minT :: (TDS d) -> Int -> Bool -> ((TDS d), TensorLong)
tds_min t dimension keepdim = unsafePerformIO $
  ret2 c_THDoubleTensor_min t dimension keepdim
{-# NOINLINE tds_min #-}

-- TH_API void THTensor_(kthvalue)(THTensor *values_, THLongTensor *indices_, THTensor *t, long k, int dimension, int keepdim);
-- tds_kthvalue :: (TDS d) -> Int -> Int -> Bool -> ((TDS d), TensorLong)
tds_kthvalue t k dimension keepdim = unsafePerformIO $
  ret2 ((swap c_THDoubleTensor_kthvalue) kC) t dimension keepdim
  where
    swap fun a b c d e f = fun b c d a e f -- curry k (4th argument)
    kC = fromIntegral k
{-# NOINLINE tds_kthvalue #-}

-- TH_API void THTensor_(mode)(THTensor *values_, THLongTensor *indices_, THTensor *t, int dimension, int keepdim);
-- tds_mode :: (TDS d) -> Int -> Bool -> ((TDS d), TensorLong)
tds_mode t dimension keepdim = unsafePerformIO $
  ret2 c_THDoubleTensor_mode t dimension keepdim
{-# NOINLINE tds_mode #-}

-- TH_API void THTensor_(median)(THTensor *values_, THLongTensor *indices_, THTensor *t, int dimension, int keepdim);
tds_median :: SingI d => (TDS d) -> Int -> Bool -> ((TDS d), TensorLong)
tds_median t dimension keepdim = unsafePerformIO $
  ret2 c_THDoubleTensor_median t dimension keepdim
{-# NOINLINE tds_median #-}

-- TODO - types
-- TH_API void THTensor_(sum)(THTensor *r_, THTensor *t, int dimension, int keepdim);
-- tds_sum :: (TDS d) -> Int -> Bool -> (TDS d)
tds_sum t dimension keepdim = unsafePerformIO $ do
  apply1 ((swap c_THDoubleTensor_sum) dimensionC keepdimC) t
  where
    swap fun a b c d = fun c d a b
    dimensionC = fromIntegral dimension
    keepdimC = if keepdim then 1 else 0
{-# NOINLINE tds_sum #-}

-- |row sums of a matrix
tds_rowsum :: (KnownNat r, KnownNat c) => TDS [r, c] -> TDS [1, c]
tds_rowsum t = tds_sum t 0 True

-- |column sums of a matrix
tds_colsum :: (KnownNat r, KnownNat c) => TDS [r, c] -> TDS [r, 1]
tds_colsum t = tds_sum t 1 True

-- TH_API void THTensor_(prod)(THTensor *r_, THTensor *t, int dimension, int keepdim);
-- tds_prod :: (TDS d) -> Int -> Bool -> (TDS d)
tds_prod t dimension keepdim = unsafePerformIO $ do
  apply1 ((swap c_THDoubleTensor_prod) dimensionC keepdimC) t
  where
    swap fun a b c d = fun c d a b
    dimensionC = fromIntegral dimension
    keepdimC = if keepdim then 1 else 0
{-# NOINLINE tds_prod #-}

-- TH_API void THTensor_(cumsum)(THTensor *r_, THTensor *t, int dimension);
-- tds_cumsum :: (TDS d) -> Int -> (TDS d)
tds_cumsum t dimension = unsafePerformIO $ do
  apply1 ((swap c_THDoubleTensor_cumsum) dimensionC) t
  where
    swap fun a b c = fun b c a
    dimensionC = fromIntegral dimension
{-# NOINLINE tds_cumsum #-}

-- TH_API void THTensor_(cumprod)(THTensor *r_, THTensor *t, int dimension);
-- tds_cumprod :: (TDS d) -> Int -> (TDS d)
tds_cumprod t dimension = unsafePerformIO $ do
  apply1 ((swap c_THDoubleTensor_cumprod) dimensionC) t
  where
    swap fun a b c = fun b c a
    dimensionC = fromIntegral dimension
{-# NOINLINE tds_cumprod #-}

-- TH_API void THTensor_(sign)(THTensor *r_, THTensor *t);
tds_sign :: SingI d => (TDS d) -> (TDS d)
tds_sign t = unsafePerformIO $ do
  apply1 c_THDoubleTensor_sign t
{-# NOINLINE tds_sign #-}

-- TH_API accreal THTensor_(trace)(THTensor *t);
tds_trace :: SingI d => (TDS d) -> Double
tds_trace t = realToFrac $ unsafePerformIO $ do
  apply0_ c_THDoubleTensor_trace t
{-# NOINLINE tds_trace #-}

-- TH_API void THTensor_(cross)(THTensor *r_, THTensor *a, THTensor *b, int dimension);
tds_cross a b dimension = unsafePerformIO $ do
  apply2 ((swap c_THDoubleTensor_cross) dimensionC) a b
  where
    dimensionC = fromIntegral dimension
    swap fun a b c d = fun b c d a
{-# NOINLINE tds_cross #-}

-- TH_API void THTensor_(cmax)(THTensor *r, THTensor *t, THTensor *src);
tds_cmax t src = unsafePerformIO $ apply2 c_THDoubleTensor_cmax t src
{-# NOINLINE tds_cmax #-}

-- TH_API void THTensor_(cmin)(THTensor *r, THTensor *t, THTensor *src);
tds_cmin t src = unsafePerformIO $ apply2 c_THDoubleTensor_cmin t src
{-# NOINLINE tds_cmin #-}

----------

-- |Test for equality between all elements of two tensors between two tensors
tds_equal :: SingI d => (TDS d) -> (TDS d) -> Bool
tds_equal ta tb = unsafePerformIO $ do
  res <- fromIntegral <$> withForeignPtr (tdsTensor ta)
         (\taPtr ->
             withForeignPtr (tdsTensor tb)
               (\tbPtr ->
                   pure $ c_THDoubleTensor_equal taPtr tbPtr
               )
         )
  pure $ res == 1
{-# NOINLINE tds_equal #-}

-- tds_geValue :: SingI d => (TDS d) -> (TDS d) -> Double -> Bool
-- tds_geValue ta tb = unsafePerformIO $ do
--   let res = tbs_new
--   res <- fromIntegral <$> withForeignPtr (tdsTensor ta)
--          (\taPtr ->
--              withForeignPtr (tdsTensor tb)
--                (\tbPtr ->
--                    pure $ c_THDoubleTensor_geValue taPtr tbPtr
--                )
--          )
--   pure $ res == 1
-- {-# NOINLINE tds_geValue #-}

-- |Concatenate two vectors
tds_cat :: forall n1 n2 n . (SingI n1, SingI n2, SingI n, n ~ Sum [n1, n2]) =>
  TDS '[n1] -> TDS '[n2] -> TDS '[n]
tds_cat ta tb = unsafePerformIO $ do
  let r_ = tds_new :: TDS '[n]
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor r_)
    taPtr <- managed $ withForeignPtr (tdsTensor ta)
    tbPtr <- managed $ withForeignPtr (tdsTensor tb)
    liftIO $ c_THDoubleTensor_cat rPtr taPtr tbPtr 0
  pure r_
{-# NOINLINE tds_cat #-}

-- |Create a diagonal matrix from a 1D vector
tds_diag :: forall d . SingI d => TDS '[d] -> TDS '[d,d]
tds_diag t = unsafePerformIO $ do
  let r_ = tds_new :: TDS '[d,d]
  runManaged $ do
    rPtr <- managed $ withForeignPtr (tdsTensor r_)
    tPtr <- managed $ withForeignPtr (tdsTensor t)
    liftIO $ c_THDoubleTensor_diag rPtr tPtr k
  pure r_
  where k = 0
{-# NOINLINE tds_diag #-}

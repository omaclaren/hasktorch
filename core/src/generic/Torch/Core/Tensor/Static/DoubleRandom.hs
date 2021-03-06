{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Torch.Core.Tensor.Static.DoubleRandom
  ( tds_random
  , tds_mvn
  , tds_clampedRandom
  , tds_cappedRandom
  , tds_geometric
  , tds_bernoulli
  , tds_bernoulliFloat
  , tds_bernoulliDouble
  , tds_uniform
  , tds_normal
  , tds_exponential
  , tds_cauchy
  , tds_multinomial

  , module Torch.Core.Random
  ) where

import Control.Monad.Managed
import Foreign
import Foreign.C.Types
import Foreign.Ptr
import Foreign.ForeignPtr (ForeignPtr, withForeignPtr)
import GHC.Ptr (FunPtr)

import Torch.Core.Tensor.Static.Double
import Torch.Core.Tensor.Static.DoubleMath
import Torch.Core.Tensor.Dynamic.Long
import Torch.Core.Tensor.Raw
import Torch.Core.Tensor.Types
import Torch.Core.Random

import THTypes
import THRandom
import THDoubleTensor
import THDoubleTensorMath
import THDoubleTensorRandom

import THFloatTensor

import Data.Singletons
import Data.Singletons.Prelude
import Data.Singletons.TypeLits

-- |generate correlated multivariate normal samples by specifying eigendecomposition
tds_mvn :: forall n p . (KnownNat n, KnownNat p) =>
  RandGen -> TDS '[p] -> TDS '[p,p] -> TDS '[p] -> IO (TDS '[n, p])
tds_mvn gen mu eigenvectors eigenvalues = do
  let offset = tds_expand mu :: TDS '[n, p]
  samps <- tds_normal gen 0.0 1.0 :: IO (TDS '[p, n])
  let result = tds_trans ((tds_trans eigenvectors)
                          !*! (tds_diag eigenvalues)
                          !*! eigenvectors
                          !*! samps) + offset
  pure result

test_mvn :: IO ()
test_mvn = do
  gen <- newRNG
  let eigenvectors = tds_fromList [1, 1, 1, 1, 1, 1, 0, 0, 0] :: TDS '[3,3]
  tds_p eigenvectors
  let eigenvalues = tds_fromList [1, 1, 1] :: TDS '[3]
  tds_p eigenvalues
  let mu = tds_fromList [0.0, 0.0, 0.0] :: TDS '[3]
  result <- tds_mvn gen mu eigenvectors eigenvalues :: IO (TDS '[10, 3])
  tds_p result

-- TODO: get rid of self parameter arguments since they are overwritten

tds_random :: SingI d => RandGen -> IO (TDS d)
tds_random gen = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO $ c_THDoubleTensor_random s g
  pure result

tds_clampedRandom gen minVal maxVal = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO $ c_THDoubleTensor_clampedRandom s g minC maxC
  pure result
  where (minC, maxC) = (fromIntegral minVal, fromIntegral maxVal)

tds_cappedRandom :: SingI d => RandGen -> Int -> IO (TDS d)
tds_cappedRandom gen maxVal = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO $ c_THDoubleTensor_cappedRandom s g maxC
  pure result
  where maxC = fromIntegral maxVal

-- TH_API void THTensor_(geometric)(THTensor *self, THGenerator *_generator, double p);
tds_geometric :: SingI d => RandGen -> Double -> IO (TDS d)
tds_geometric gen p = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO $ c_THDoubleTensor_geometric s g pC
  pure result
  where pC = realToFrac p

-- TH_API void THTensor_(bernoulli)(THTensor *self, THGenerator *_generator, double p);
tds_bernoulli :: SingI d => RandGen -> Double -> IO (TDS d)
tds_bernoulli gen p = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO $ c_THDoubleTensor_bernoulli s g pC
  pure result
  where pC = realToFrac p

tds_bernoulliFloat :: SingI d => RandGen -> TensorFloat -> IO (TDS d)
tds_bernoulliFloat gen p = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    pC <- managed (withForeignPtr (tfTensor p))
    liftIO (c_THDoubleTensor_bernoulli_FloatTensor s g pC)
  pure result

tds_bernoulliDouble :: SingI d => RandGen -> TDS d -> IO (TDS d)
tds_bernoulliDouble gen p = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    pC <- managed (withForeignPtr (tdsTensor p))
    liftIO (c_THDoubleTensor_bernoulli_DoubleTensor s g pC)
  pure result
  where pC = tdsTensor p

tds_uniform :: SingI d => RandGen -> Double -> Double -> IO (TDS d)
tds_uniform gen a b = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO (c_THDoubleTensor_uniform s g aC bC)
  pure result
  where aC = realToFrac a
        bC = realToFrac b

tds_normal :: SingI d => RandGen -> Double -> Double -> IO (TDS d)
tds_normal gen mean stdv = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO (c_THDoubleTensor_normal s g meanC stdvC)
  pure result
  where meanC = realToFrac mean
        stdvC = realToFrac stdv

-- TH_API void THTensor_(normal_means)(THTensor *self, THGenerator *gen, THTensor *means, double stddev);
-- TH_API void THTensor_(normal_stddevs)(THTensor *self, THGenerator *gen, double mean, THTensor *stddevs);
-- TH_API void THTensor_(normal_means_stddevs)(THTensor *self, THGenerator *gen, THTensor *means, THTensor *stddevs);

tds_exponential :: SingI d => RandGen -> Double -> IO (TDS d)
tds_exponential gen lambda = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO (c_THDoubleTensor_exponential s g lambdaC)
  pure result
  where lambdaC = realToFrac lambda

tds_cauchy :: SingI d => RandGen -> Double -> Double -> IO (TDS d)
tds_cauchy gen median sigma = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO (c_THDoubleTensor_cauchy s g medianC sigmaC)
  pure result
  where medianC = realToFrac median
        sigmaC = realToFrac sigma

tds_logNormal :: SingI d => RandGen -> Double -> Double -> IO (TDS d)
tds_logNormal gen mean stdv = do
  let result = tds_new
  runManaged $ do
    s <- managed (withForeignPtr (tdsTensor result))
    g <- managed (withForeignPtr (rng gen))
    liftIO (c_THDoubleTensor_logNormal s g meanC stdvC)
  pure result
  where meanC = realToFrac mean
        stdvC = realToFrac stdv

tds_multinomial :: SingI d => RandGen -> TDS d -> Int -> Bool -> TensorDim Word -> IO (TensorLong)
tds_multinomial gen prob_dist n_sample with_replacement dim = do
  let result = tl_new dim
  runManaged $ do
    s <- managed (withForeignPtr (tlTensor result))
    g <- managed (withForeignPtr (rng gen))
    p <- managed (withForeignPtr (tdsTensor prob_dist))
    liftIO (c_THDoubleTensor_multinomial s g p n_sampleC with_replacementC)
  pure result
  where n_sampleC = fromIntegral n_sample
        with_replacementC = if with_replacement then 1 else 0

-- TH_API void THTensor_(multinomialAliasSetup)(THTensor *prob_dist, THLongTensor *J, THTensor *q);
-- TH_API void THTensor_(multinomialAliasDraw)(THLongTensor *self, THGenerator *_generator, THLongTensor *J, THTensor *q);
-- #endif


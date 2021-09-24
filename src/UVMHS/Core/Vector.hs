module UVMHS.Core.Vector
  ( module UVMHS.Core.Vector
  , module Foreign.Storable
  ) where

import UVMHS.Core.Init
import UVMHS.Core.Monads ()

import UVMHS.Core.Classes
import UVMHS.Core.Data
import UVMHS.Core.Sized

import Foreign.Storable (Storable(..))

import qualified Data.Vector                  as VB
import qualified Data.Vector.Mutable          as VBM
import qualified Data.Vector.Storable         as VU

-------
-- 𝕍 --
-------

newtype 𝕍 a = 𝕍 { un𝕍 ∷ VB.Vector a }
  deriving (Eq,Ord)

instance ToStream a (𝕍 a)      where stream = stream𝕍
instance ToIter a (𝕍 a)        where iter   = iter ∘ stream
instance (Show a) ⇒ Show (𝕍 a) where show   = chars ∘ show𝕍
instance Lookup ℕ64 a (𝕍 a)    where (⋕?)   = flip idx𝕍
instance Functor 𝕍             where map    = map𝕍
instance FunctorM 𝕍            where mapM   = mapM𝕍

vec ∷ (ToIter a t) ⇒ t → 𝕍 a
vec = 𝕍 ∘ VB.fromList ∘ lazyList

vecC ∷ (ToIterC a t) ⇒ t → 𝕍 a
vecC xs =
  let xsi = iterC xs
  in 𝕍 $ VB.fromListN (tohs $ intΩ64 $ csize xsi) $ lazyList xsi

vecF ∷ ℕ64 → (ℕ64 → a) → 𝕍 a
vecF n f = vecC $ map f $ upToC n

vecDΩ ∷ ℕ64 ⇰ a → 𝕍 a
vecDΩ d = case dmaxKey d of
  None → vec empty𝐼
  Some k → vecF (k + one) $ \ n → d ⋕! n

stream𝕍 ∷ 𝕍 a → 𝑆 a
stream𝕍 xs = stream $ VB.toList $ un𝕍 xs

show𝕍 ∷ (Show a) ⇒ 𝕍 a → 𝕊
show𝕍 = showCollection "𝕍[" "]" "," show𝕊 ∘ iter

idx𝕍 ∷ ℕ64 → 𝕍 a → 𝑂 a
idx𝕍 i xs = frhs $ un𝕍 xs VB.!? tohs (intΩ64 i)

idx𝕍Ω ∷ ℕ64 → 𝕍 a → a
idx𝕍Ω i xs = un𝕍 xs VB.! tohs (intΩ64 i)

idx𝕍Ω_UNSAFE ∷ ℕ64 → 𝕍 a → a
idx𝕍Ω_UNSAFE i xs = un𝕍 xs `VB.unsafeIndex` tohs (intΩ64 i)

map𝕍 ∷ (a → b) → 𝕍 a → 𝕍 b
map𝕍 f = 𝕍 ∘ VB.map f ∘ un𝕍

mapM𝕍 ∷ ∀ m a b. (Monad m) ⇒ (a → m b) → 𝕍 a → m (𝕍 b)
mapM𝕍 f = with (tohsMonad @ m) $ 𝕍 ^∘ VB.mapM f ∘ un𝕍

null𝕍 ∷ (Null a) ⇒ ℕ64 → 𝕍 a
null𝕍 n = vecF n $ const null

----------
--- 𝕍M ---
----------

newtype 𝕍Mut a = 𝕍Mut { un𝕍Mut ∷ VBM.IOVector a }

vec𝕍Mut ∷ (ToIter a t) ⇒ t → IO (𝕍Mut a)
vec𝕍Mut xs = do
  v ← VBM.new $ tohs n
  eachOn (withIndex xs) $ \ (i :* x) → VBM.write v (tohs i) x
  return $ 𝕍Mut v
  where n = count xs

idx𝕍Mut ∷ ℕ64 → 𝕍Mut a → a
idx𝕍Mut i v = do
  x ← VBM.read (un𝕍Mut v) (tohs i)
  return $ frhs x

{-

instance ToStream a (𝕍 a)      where stream = stream𝕍
instance ToIter a (𝕍 a)        where iter   = iter ∘ stream
instance (Show a) ⇒ Show (𝕍 a) where show   = chars ∘ show𝕍
instance Lookup ℕ64 a (𝕍 a)    where (⋕?)   = flip idx𝕍
instance Functor 𝕍             where map    = map𝕍
instance FunctorM 𝕍            where mapM   = mapM𝕍

vec ∷ (ToIter a t) ⇒ t → 𝕍 a
vec = 𝕍 ∘ VB.fromList ∘ lazyList

vecC ∷ (ToIterC a t) ⇒ t → 𝕍 a
vecC xs =
  let xsi = iterC xs
  in 𝕍 $ VB.fromListN (tohs $ intΩ64 $ csize xsi) $ lazyList xsi

vecF ∷ ℕ64 → (ℕ64 → a) → 𝕍 a
vecF n f = vecC $ map f $ upToC n

vecDΩ ∷ ℕ64 ⇰ a → 𝕍 a
vecDΩ d = case dmaxKey d of
  None → vec empty𝐼
  Some k → vecF (k + one) $ \ n → d ⋕! n

stream𝕍 ∷ 𝕍 a → 𝑆 a
stream𝕍 xs = stream $ VB.toList $ un𝕍 xs

show𝕍 ∷ (Show a) ⇒ 𝕍 a → 𝕊
show𝕍 = showCollection "𝕍[" "]" "," show𝕊 ∘ iter

idx𝕍 ∷ ℕ64 → 𝕍 a → 𝑂 a
idx𝕍 i xs = frhs $ un𝕍 xs VB.!? tohs (intΩ64 i)

idx𝕍Ω ∷ ℕ64 → 𝕍 a → a
idx𝕍Ω i xs = un𝕍 xs VB.! tohs (intΩ64 i)

idx𝕍Ω_UNSAFE ∷ ℕ64 → 𝕍 a → a
idx𝕍Ω_UNSAFE i xs = un𝕍 xs `VB.unsafeIndex` tohs (intΩ64 i)

map𝕍 ∷ (a → b) → 𝕍 a → 𝕍 b
map𝕍 f = 𝕍 ∘ VB.map f ∘ un𝕍

mapM𝕍 ∷ ∀ m a b. (Monad m) ⇒ (a → m b) → 𝕍 a → m (𝕍 b)
mapM𝕍 f = with (tohsMonad @ m) $ 𝕍 ^∘ VB.mapM f ∘ un𝕍

null𝕍 ∷ (Null a) ⇒ ℕ64 → 𝕍 a
null𝕍 n = vecF n $ const null
-}

-------
-- 𝕌 --
-------

newtype 𝕌 a = 𝕌 { un𝕌 ∷ VU.Vector a }
  deriving (Eq,Ord)

instance (Storable a) ⇒ ToStream a (𝕌 a)   where stream = stream𝕌
instance (Storable a) ⇒ ToIter a (𝕌 a)     where iter   = iter ∘ stream
instance (Storable a,Show a) ⇒ Show (𝕌 a)  where show   = chars ∘ show𝕌
instance (Storable a) ⇒ Lookup ℕ64 a (𝕌 a) where (⋕?)   = flip idx𝕌

uvec ∷ (Storable a,ToIter a t) ⇒ t → 𝕌 a
uvec = 𝕌 ∘ VU.fromList ∘ lazyList

uvecC ∷ (Storable a,ToIterC a t) ⇒ t → 𝕌 a
uvecC xs =
  let xsi = iterC xs
  in 𝕌 $ VU.fromListN (tohs $ intΩ64 $ csize xsi) $ lazyList xsi

uvecF ∷ (Storable a) ⇒ ℕ64 → (ℕ64 → a) → 𝕌 a
uvecF n f = uvec $ map f $ upTo n

uvecDΩ ∷ (Storable a) ⇒ ℕ64 ⇰ a → 𝕌 a
uvecDΩ d = case dmaxKey d of
  None → uvec empty𝐼
  Some k → uvecF (k + one) $ \ n → d ⋕! n

stream𝕌 ∷ (Storable a) ⇒ 𝕌 a → 𝑆 a
stream𝕌 xs = stream $ VU.toList $ un𝕌 xs

show𝕌 ∷ (Storable a,Show a) ⇒ 𝕌 a → 𝕊
show𝕌 = showCollection "𝕌[" "]" "," show𝕊 ∘ iter

idx𝕌 ∷ (Storable a) ⇒ ℕ64 → 𝕌 a → 𝑂 a
idx𝕌 i xs = frhs $ un𝕌 xs VU.!? tohs (intΩ64 i)

idx𝕌Ω ∷ (Storable a) ⇒ ℕ64 → 𝕌 a → a
idx𝕌Ω i xs = frhs $ un𝕌 xs VU.! tohs (intΩ64 i)

idx𝕌Ω_UNSAFE ∷ (Storable a) ⇒ ℕ64 → 𝕌 a → a
idx𝕌Ω_UNSAFE i xs = frhs $ un𝕌 xs `VU.unsafeIndex` tohs (intΩ64 i)

map𝕌 ∷ (Storable a,Storable b) ⇒ (a → b) → 𝕌 a → 𝕌 b
map𝕌 f = 𝕌 ∘ VU.map f ∘ un𝕌

mapM𝕌 ∷ ∀ m a b. (Monad m,Storable a,Storable b) ⇒ (a → m b) → 𝕌 a → m (𝕌 b)
mapM𝕌 f = with (tohsMonad @ m) $ 𝕌 ^∘ VU.mapM f ∘ un𝕌

null𝕌 ∷ (Storable a,Null a) ⇒ ℕ64 → 𝕌 a
null𝕌 n = uvecF n $ const null

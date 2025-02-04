module UVMHS.Core.FilePath where

import UVMHS.Core.Init
import UVMHS.Core.Data
import UVMHS.Core.Classes

import qualified System.FilePath as FP

-- FilePath
newtype ℙ = ℙ { unℙ ∷ 𝕊 }
  deriving (Eq,Ord,Show)

instance Null ℙ where null = pnull
instance Append ℙ where (⧺) = pappend
instance Monoid ℙ

pnull ∷ ℙ
pnull = ℙ ""

pappend ∷ ℙ → ℙ → ℙ
pappend x y = ℙ $ string $ tohsChars (unℙ x) FP.</> tohsChars (unℙ y)

pfilename ∷ ℙ → ℙ
pfilename = ℙ ∘ string ∘ FP.takeFileName ∘ tohsChars ∘ unℙ

pbasename ∷ ℙ → ℙ
pbasename = ℙ ∘ string ∘ FP.takeBaseName ∘ tohsChars ∘ unℙ

pdirectory ∷ ℙ → ℙ
pdirectory = ℙ ∘ string ∘ FP.takeDirectory ∘ tohsChars ∘ unℙ

pextension ∷ ℙ → ℙ
pextension = ℙ ∘ string ∘ FP.takeExtension ∘ tohsChars ∘ unℙ

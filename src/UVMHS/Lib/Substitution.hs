module UVMHS.Lib.Substitution where

import UVMHS.Core
import UVMHS.Lib.Annotated
import UVMHS.Lib.Variables
import UVMHS.Lib.Testing
import UVMHS.Lib.Rand
import UVMHS.Lib.Pretty

import UVMHS.Lang.ULCD

-- ===================== --
-- DEBRUIJN SUBSTITUTION --
-- ===================== --

-- ℯ ⩴ i | ⟨ι,e⟩
data DSubstElem e = 
    Var_DSE ℤ64
  | Trm_DSE ℤ64 (() → 𝑂 e)

instance (Eq a) ⇒ Eq (DSubstElem a) where
  𝓈₁ == 𝓈₂ = case (𝓈₁,𝓈₂) of
    (Var_DSE i₁,Var_DSE i₂) → i₁ ≡ i₂
    (Trm_DSE ι₁ ueO₁,Trm_DSE ι₂ ueO₂) → ι₁ ≡ ι₂ ⩓ ueO₁ () ≡ ueO₂ ()
    _ → False

instance (Pretty a) ⇒ Pretty (DSubstElem a) where
  pretty = \case
    Var_DSE i → pretty $ DVar i
    Trm_DSE ι e → concat
      [ ppPun $ show𝕊 ι
      , ppPun "⇈"
      , ifNone (ppPun "bu") $ pretty ^$ e ()
      ]

-- 𝓈 ⩴ ⟨ρ,ι,[e…e]⟩
data DSubst e = DSubst
  { dsubstShift ∷ ℤ64
  , dsubstIntro ∷ ℤ64
  , dsubstElems ∷ 𝕍 (DSubstElem e)
  } deriving (Eq)
makeLenses ''DSubst
makePrettyRecord ''DSubst

𝓈shift ∷ ℤ64 → DSubst e → DSubst e
𝓈shift ρ' (DSubst ρ ι es) =
  DSubst (ρ+ρ') ι $ mapOn es $ \case
    Var_DSE i → Var_DSE $ i + ρ'
    Trm_DSE ι' ueO → Trm_DSE (ι' + ρ') ueO

𝓈intro ∷ ℤ64 → DSubst e
𝓈intro ι = DSubst 0 ι null

𝓈binds ∷ 𝕍 e → DSubst e
𝓈binds es = DSubst 0 (neg $ intΩ64 $ csize es) $ map (Trm_DSE 0 ∘ const ∘ return) es

𝓈bind ∷ e → DSubst e
𝓈bind = 𝓈binds ∘ single

-- 𝓈 ≜ ⟨ρ,ι,ℯs⟩
-- 𝓈(i) |          i < ρ      = i
--      |      ρ ≤ i < |ℯs|+ρ = ℯs[i-ρ]
--      | |ℯs|+ρ ≤ i          = i + ι
-- e.g.,
-- 𝓈 = ⟨2,-1,[e₁,e₂]⟩
-- 𝓈 is logically equivalent to the (infinite) substitution vector
-- [ …
-- , -2 ↦ ⌊-2⌋
-- , -1 ↦ ⌊-1⌋
-- ,  0 ↦ ⌊0⌋
-- ,  1 ↦ ⌊1⌋
-- ,  2 ↦ e₁
-- ,  3 ↦ e₂
-- ,  4 ↦ ⌊3⌋
-- ,  5 ↦ ⌊4⌋
-- , …
-- ]
-- 𝓈 = ⟨-2,1,[e₁,e₂,e₃,e₄]⟩
-- 𝓈 is logically equivalent to the (infinite) substitution vector
-- [ …
-- , -4 ↦ ⌊-4⌋
-- , -3 ↦ ⌊-3⌋
-- , -2 ↦ e₁
-- , -1 ↦ e₂
-- ,  0 ↦ e₃
-- ,  1 ↦ e₄
-- ,  2 ↦ ⌊3⌋
-- ,  3 ↦ ⌊4⌋
-- ,  4 ↦ ⌊5⌋
-- ,  5 ↦ ⌊6⌋
-- , …
-- ]
dsubstVar ∷ DSubst e → ℤ64 → DSubstElem e
dsubstVar (DSubst ρ ι ℯs) i =
  if i < ρ
  then Var_DSE i
  else 
  let ℯO = do
        n ← natO64 $ i - ρ
        ℯs ⋕? n
  in case ℯO of
    None → Var_DSE $ i + ι
    Some ℯ → ℯ

-- esubst(ι,σ,e) ≡ σ(ι(e))
dsubstElem ∷ (ℤ64 → DSubst e → e → 𝑂 e) → DSubst e → DSubstElem e → DSubstElem e
dsubstElem esubst 𝓈 = \case
  Var_DSE n → dsubstVar 𝓈 n
  Trm_DSE ι ueO → Trm_DSE 0 $ \ () → esubst ι 𝓈 *$ ueO ()

-----------------
-- COMPOSITION --
-----------------

-- 𝓈₁ ≜ ⟨ρ₁,ι₁,ℯs₁⟩
-- 𝓈₂ ≜ ⟨ρ₂,ι₂,ℯs₂⟩
-- (𝓈₂⧺𝓈₁)(i) 
-- ==
-- 𝓈₂(𝓈₁(i))
-- ==
-- cases:
--              i < ρ₁       ⇒ 𝓈₂(i)
--         ρ₁ ≤ i < |ℯs₁|+ρ₁ ⇒ 𝓈₂(ℯs₁[i-ρ₁])
--   |ℯs₁|+ρ₁ ≤ i            ⇒ 𝓈₂(i+ι₁)
-- ==
-- cases:
--              i < ρ₁       ⇒ cases:
--                                          i < ρ₂       ⇒ i
--                                     ρ₂ ≤ i < |ℯs₂|+ρ₂ ⇒ ℯs₂[i-ρ₂]
--                               |ℯs₂|+ρ₂ ≤ i            ⇒ i + ι₂
--         ρ₁ ≤ i < |ℯs₁|+ρ₁ ⇒ 𝓈₂(ℯs₁(i-ρ₁))
--   |ℯs₁|+ρ₁ ≤ i            ⇒ cases:
--                                          i+ι₁ < ρ₂       ⇒ i+ι₁
--                                     ρ₂ ≤ i+ι₁ < |ℯs₂|+ρ₂ ⇒ ℯs₂[i+ι₁-ρ₂]
--                               |ℯs₂|+ρ₂ ≤ i+ι₁            ⇒ i+ι₁+ι₂
-- ==
-- cases:
--   i  < ρ₁      ∧            i    < ρ₂       ⇒ i
--   i  < ρ₁      ∧       ρ₂ ≤ i    < |ℯs₂|+ρ₂ ⇒ ℯs₂[i-ρ₂]
--   i  < ρ₁      ∧ |ℯs₂|+ρ₂ ≤ i               ⇒ i + ι₂
--   ρ₁ ≤ i       ∧            i < |ℯs₁|+ρ₁    ⇒ 𝓈₂(ℯs₁[i-ρ₁])
--   |ℯs₁|+ρ₁ ≤ i ∧            i+ι₁ < ρ₂       ⇒ i+ι₁
--   |ℯs₁|+ρ₁ ≤ i ∧       ρ₂ ≤ i+ι₁ < |ℯs₂|+ρ₂ ⇒ ℯs₂[i+ι₁-ρ₂]
--   |ℯs₁|+ρ₁ ≤ i ∧ |ℯs₂|+ρ₂ ≤ i+ι₁            ⇒ i + ι₁ + ι₂
-- ==
-- cases:
--                              i < ρ₁⊓ρ₂         ⇒ i
--                         ρ₂ ≤ i < ρ₁⊓(|ℯs₂|+ρ₂) ⇒ ℯs₂[i-ρ₂]
--                   |ℯs₂|+ρ₂ ≤ i < ρ₁            ⇒ i + ι₂
--                         ρ₁ ≤ i < |ℯs₁|+ρ₁      ⇒ 𝓈₂(ℯs₁[i-ρ₁])
--                   |ℯs₁|+ρ₁ ≤ i < ρ₂-ι₁         ⇒ i+ι₁
--         (|ℯs₁|+ρ₁)⊔(ρ₂-ι₁) ≤ i < |ℯs₂|+ρ₂-ι₁   ⇒ ℯs₂[i+ι₁-ρ₂]
--   (|ℯs₁|+ρ₁)⊔(|ℯs₂|+ρ₂-ι₁) ≤ i                 ⇒ i + ι₁ + ι₂
-- ==                  
-- ⟨ρ₁⊓ρ₁,ι₁+ι₂,ℯs⟩ where
--   ℯs[i-(ρ₁⊓ρ₂)] |                 ρ₂ ≤ i < ρ₁⊓(|ℯs₂|+ρ₂) ≡ ℯs₂[i-ρ₂]
--   ℯs[i-(ρ₁⊓ρ₂)] |           |ℯs₂|+ρ₂ ≤ i < ρ₁            ≡ i + ι₂
--   ℯs[i-(ρ₁⊓ρ₂)] |                 ρ₁ ≤ i < |ℯs₁|+ρ₁      ≡ 𝓈₂(ℯs₁[i-ρ₁])
--   ℯs[i-(ρ₁⊓ρ₂)] |           |ℯs₁|+ρ₁ ≤ i < ρ₂-ι₁         ≡ i+ι₁
--   ℯs[i-(ρ₁⊓ρ₂)] | (|ℯs₁|+ρ₁)⊔(ρ₂-ι₁) ≤ i < |ℯs₂|+ρ₂-ι₁   ≡ ℯs₂[i+ι₁-ρ₂]
-- ==                  
-- ⟨ρ₁⊓ρ₁,ι₁+ι₂,ℯs⟩ where
--   ℯs[i-(ρ₁⊓ρ₂)] |                   ρ₂-(ρ₁⊓ρ₂) ≤ i-(ρ₁⊓ρ₂) < (ρ₁⊓(|ℯs₂|+ρ₂))-(ρ₁⊓ρ₂) ≡ ℯs₂[i-ρ₂]
--   ℯs[i-(ρ₁⊓ρ₂)] |             |ℯs₂|+ρ₂-(ρ₁⊓ρ₂) ≤ i-(ρ₁⊓ρ₂) < ρ₁-(ρ₁⊓ρ₂)              ≡ i + ι₂
--   ℯs[i-(ρ₁⊓ρ₂)] |                   ρ₁-(ρ₁⊓ρ₂) ≤ i-(ρ₁⊓ρ₂) < |ℯs₁|+ρ₁-(ρ₁⊓ρ₂)        ≡ 𝓈₂(ℯs₁[i-ρ₁])
--   ℯs[i-(ρ₁⊓ρ₂)] |             |ℯs₁|+ρ₁-(ρ₁⊓ρ₂) ≤ i-(ρ₁⊓ρ₂) < ρ₂-ι₁-(ρ₁⊓ρ₂)           ≡ i+ι₁
--   ℯs[i-(ρ₁⊓ρ₂)] | ((|ℯs₁|+ρ₁)⊔(ρ₂-ι₁))-(ρ₁⊓ρ₂) ≤ i-(ρ₁⊓ρ₂) < |ℯs₂|+ρ₂-ι₁-(ρ₁⊓ρ₂)     ≡ ℯs₂[i+ι₁-ρ₂]
-- == (n = i-(ρ₁⊓ρ₂))
-- ⟨ρ₁⊓ρ₁,ι₁+ι₂,ℯs⟩ where
--   ℯs[n] |                   ρ₂-(ρ₁⊓ρ₂) ≤ n < (ρ₁⊓(|ℯs₂|+ρ₂))-(ρ₁⊓ρ₂) ≡ ℯs₂[n+(ρ₁⊓ρ₂)-ρ₂]
--   ℯs[n] |             |ℯs₂|+ρ₂-(ρ₁⊓ρ₂) ≤ n < ρ₁-(ρ₁⊓ρ₂)              ≡ n+(ρ₁⊓ρ₂)+ι₂
--   ℯs[n] |                   ρ₁-(ρ₁⊓ρ₂) ≤ n < |ℯs₁|+ρ₁-(ρ₁⊓ρ₂)        ≡ 𝓈₂(ℯs₁[n+(ρ₁⊓ρ₂)-ρ₁])
--   ℯs[n] |             |ℯs₁|+ρ₁-(ρ₁⊓ρ₂) ≤ n < ρ₂-ι₁-(ρ₁⊓ρ₂)           ≡ n+(ρ₁⊓ρ₂)+ι₁
--   ℯs[n] | ((|ℯs₁|+ρ₁)⊔(ρ₂-ι₁))-(ρ₁⊓ρ₂) ≤ n < |ℯs₂|+ρ₂-ι₁-(ρ₁⊓ρ₂)     ≡ ℯs₂[n+(ρ₁⊓ρ₂)+ι₁-ρ₂]

dsubstAppend ∷ (DSubst e → e → 𝑂 e) → DSubst e → DSubst e → DSubst e
dsubstAppend esubst 𝓈₂@(DSubst ρ₂ ι₂ ℯs₂) (DSubst ρ₁ ι₁ ℯs₁) =
  let ρ = ρ₁ ⊓ ρ₂
      ι = ι₁ + ι₂
      𝑠₁ = intΩ64 $ csize ℯs₁
      𝑠₂ = intΩ64 $ csize ℯs₂
      𝑠 = natΩ64 $ joins
        [ 0
        , 𝑠₂ + ρ₂ - (ρ₁ ⊓ ρ₂) - ι₁ 
        , 𝑠₁ + ρ₁ - (ρ₁ ⊓ ρ₂)
        ]
      sub = dsubstElem $ \ ι' 𝓈' → esubst $ dsubstAppend esubst 𝓈' $ DSubst 0 ι' null
      ℯs = vecF 𝑠 $ \ n →
        let i = intΩ64 n
        in if
        |                ρ₂-(ρ₁⊓ρ₂) ≤ i ⩓ i < (ρ₁⊓(𝑠₂+ρ₂))-(ρ₁⊓ρ₂) → ℯs₂ ⋕! natΩ64 (i+(ρ₁⊓ρ₂)-ρ₂)
        |             𝑠₂+ρ₂-(ρ₁⊓ρ₂) ≤ i ⩓ i < ρ₁-(ρ₁⊓ρ₂)           → Var_DSE $ i+(ρ₁⊓ρ₂)+ι₂
        |                ρ₁-(ρ₁⊓ρ₂) ≤ i ⩓ i < 𝑠₁+ρ₁-(ρ₁⊓ρ₂)        → sub 𝓈₂ $ ℯs₁ ⋕! natΩ64 (i+(ρ₁⊓ρ₂)-ρ₁)
        |             𝑠₁+ρ₁-(ρ₁⊓ρ₂) ≤ i ⩓ i < ρ₂-ι₁-(ρ₁⊓ρ₂)        → Var_DSE $ i+(ρ₁⊓ρ₂)+ι₁
        | ((𝑠₁+ρ₁)⊔(ρ₂-ι₁))-(ρ₁⊓ρ₂) ≤ i ⩓ i < 𝑠₂+ρ₂-ι₁-(ρ₁⊓ρ₂)     → ℯs₂ ⋕! natΩ64 (i+(ρ₁⊓ρ₂)+ι₁-ρ₂)
        | otherwise                                                → error "impossible"
  in DSubst ρ ι ℯs

-- ====== --
-- SUBSTY --
-- ====== --

newtype SubstT e a = SubstT { unSubstT ∷ UContT (ReaderT (DSubst e) (FailT ID)) a }
  deriving
  ( Return,Bind,Functor,Monad
  , MonadUCont
  , MonadReader (DSubst e)
  , MonadFail
  )

runSubstT ∷ DSubst e → SubstT e a → 𝑂 a
runSubstT γ = unID ∘ unFailT ∘ runReaderT γ ∘ evalUContT ∘ unSubstT

class Substy e a | a→e where
  substy ∷ a → SubstT e a

subst ∷ (Substy e a) ⇒ DSubst e → a → 𝑂 a
subst 𝓈 x = runSubstT 𝓈 $ substy x

instance                Null (DSubst e)   where null = DSubst 0 0 null
instance (Substy e e) ⇒ Append (DSubst e) where (⧺) = dsubstAppend subst
instance (Substy e e) ⇒ Monoid (DSubst e)

substyDBdr ∷ SubstT e ()
substyDBdr = umodifyEnv $ 𝓈shift 1

substyDVar ∷ (Substy e e) ⇒ (ℤ64 → e) → ℤ64 → SubstT e e
substyDVar 𝓋 i = do
  𝓈 ← ask
  case dsubstVar 𝓈 i of
    Var_DSE i' → return $ 𝓋 i'
    Trm_DSE ι ueO → failEff $ subst (𝓈intro ι) *$ ueO ()


-- ======== --
-- FOR ULCD --
-- ======== --

instance Substy (ULCDExp 𝒸) (ULCDExp 𝒸) where
  substy = pipe unULCDExp $ \ (𝐴 𝒸 e₀) → ULCDExp ^$ case e₀ of
    Var_ULCD y → case y of
      DVar i → unULCDExp ^$ substyDVar (ULCDExp ∘ 𝐴 𝒸 ∘ Var_ULCD ∘ DVar) i
      _      → return $ 𝐴 𝒸 $ Var_ULCD y
    Lam_ULCD e → ureset $ do
      substyDBdr
      e' ← substy e
      return $ 𝐴 𝒸 $ Lam_ULCD e'
    App_ULCD e₁ e₂ → do
      e₁' ← substy e₁
      e₂' ← substy e₂
      return $ 𝐴 𝒸 $ App_ULCD e₁' e₂'

prandDVar ∷ ℕ64 → ℕ64 → State RG ℤ64
prandDVar nˢ nᵇ = prandr (neg $ intΩ64 nˢ) $ intΩ64 $ nᵇ + nˢ

prandNVar ∷ ℕ64 → State RG 𝕏
prandNVar nˢ = flip 𝕏 "x" ∘ Some ^$ prandr 0 nˢ

-- TODO: be aware of named scope
prandVar ∷ ℕ64 → ℕ64 → State RG 𝕐
prandVar nˢ nᵇ = mjoin $ prchoose
  [ \ () → DVar ^$ prandDVar nˢ nᵇ
  , \ () → NVar 0 ^$ prandNVar nˢ
  ]

prandULCDExp ∷ ℕ64 → ℕ64 → ℕ64 → State RG ULCDExpR
prandULCDExp nˢ nᵇ nᵈ = ULCDExp ∘ 𝐴 () ^$ mjoin $ prwchoose
    [ (2 :*) $ \ () → do
        Var_ULCD ^$ prandVar nˢ nᵇ
    , (nᵈ :*) $ \ () → do
        Lam_ULCD ^$ prandULCDExp nˢ (nᵇ + 1) $ nᵈ - 1
    , (nᵈ :*) $ \ () → do
        e₁ ← prandULCDExp nˢ nᵇ $ nᵈ - 1
        e₂ ← prandULCDExp nˢ nᵇ $ nᵈ - 1
        return $ App_ULCD e₁ e₂
    ]

instance Rand ULCDExpR where prand = flip prandULCDExp zero

prandSubstElem ∷ (Rand a) ⇒ ℕ64 → ℕ64 → State RG (DSubstElem a)
prandSubstElem nˢ nᵈ = mjoin $ prchoose
  [ \ () → do
      i ← prand nˢ nᵈ
      return $ Var_DSE i
  , \ () → do
      ι ← prand nˢ nᵈ
      e ← prand nˢ nᵈ
      return $ Trm_DSE ι $ const $ return e
  ]

instance (Rand a) ⇒ Rand (DSubstElem a) where prand = prandSubstElem

prandSSubst ∷ (Rand a) ⇒ ℕ64 → ℕ64 → State RG (DSubst a)
prandSSubst nˢ nᵈ = do
  ρ ← prand nˢ nᵈ
  ι ← prand nˢ nᵈ
  esSize ← prandr zero nˢ
  es ← mapMOn (vecF esSize id) $ const $ prand nˢ nᵈ
  return $ DSubst ρ ι es

instance (Rand a) ⇒  Rand (DSubst a) where prand = prandSSubst

-- basic --

𝔱 "subst:id" [| subst null [ulcd| λ → 0   |] |] [| Some [ulcd| λ → 0   |] |]
𝔱 "subst:id" [| subst null [ulcd| λ → 1   |] |] [| Some [ulcd| λ → 1   |] |]
𝔱 "subst:id" [| subst null [ulcd| λ → 2   |] |] [| Some [ulcd| λ → 2   |] |]
𝔱 "subst:id" [| subst null [ulcd| λ → 0 2 |] |] [| Some [ulcd| λ → 0 2 |] |]

𝔱 "subst:intro" [| subst (𝓈intro 1) [ulcd| λ → 0   |] |] [| Some [ulcd| λ → 0   |] |]
𝔱 "subst:intro" [| subst (𝓈intro 1) [ulcd| λ → 1   |] |] [| Some [ulcd| λ → 2   |] |]
𝔱 "subst:intro" [| subst (𝓈intro 1) [ulcd| λ → 2   |] |] [| Some [ulcd| λ → 3   |] |]
𝔱 "subst:intro" [| subst (𝓈intro 1) [ulcd| λ → 0 2 |] |] [| Some [ulcd| λ → 0 3 |] |]

𝔱 "subst:intro" [| subst (𝓈intro 2) [ulcd| λ → 0   |] |] [| Some [ulcd| λ → 0   |] |]
𝔱 "subst:intro" [| subst (𝓈intro 2) [ulcd| λ → 1   |] |] [| Some [ulcd| λ → 3   |] |]
𝔱 "subst:intro" [| subst (𝓈intro 2) [ulcd| λ → 2   |] |] [| Some [ulcd| λ → 4   |] |]
𝔱 "subst:intro" [| subst (𝓈intro 2) [ulcd| λ → 0 2 |] |] [| Some [ulcd| λ → 0 4 |] |]

𝔱 "subst:bind" [| subst (𝓈bind [ulcd| λ → 0 |]) [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0     |] |]
𝔱 "subst:bind" [| subst (𝓈bind [ulcd| λ → 1 |]) [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0     |] |]
𝔱 "subst:bind" [| subst (𝓈bind [ulcd| λ → 0 |]) [ulcd| λ → 1 |] |] [| Some [ulcd| λ → λ → 0 |] |]
𝔱 "subst:bind" [| subst (𝓈bind [ulcd| λ → 1 |]) [ulcd| λ → 1 |] |] [| Some [ulcd| λ → λ → 2 |] |]

𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 0 |]) [ulcd| λ → 0 |] |] 
                 [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 1 |]) [ulcd| λ → 0 |] |] 
                 [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 0 |]) [ulcd| λ → 1 |] |] 
                 [| Some [ulcd| λ → 1 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 1 |]) [ulcd| λ → 1 |] |] 
                 [| Some [ulcd| λ → 1 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 2 |]) [ulcd| λ → 0 |] |] 
                 [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 2 |]) [ulcd| λ → 1 |] |] 
                 [| Some [ulcd| λ → 1 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 1 |]) [ulcd| λ → 2 |] |] 
                 [| Some [ulcd| λ → λ → 3 |] |]
𝔱 "subst:shift" [| subst (𝓈shift 1 $ 𝓈bind [ulcd| λ → 2 |]) [ulcd| λ → 2 |] |] 
                 [| Some [ulcd| λ → λ → 4 |] |]

-- append --

𝔱 "subst:⧺" [| subst null            [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:⧺" [| subst (null ⧺ null)   [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:⧺" [| subst (𝓈shift 1 null) [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:⧺" [| subst (𝓈shift 2 null) [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0 |] |]

𝔱 "subst:⧺" [| subst null          [ulcd| λ → 1 |] |] [| Some [ulcd| λ → 1 |] |]
𝔱 "subst:⧺" [| subst (null ⧺ null) [ulcd| λ → 1 |] |] [| Some [ulcd| λ → 1 |] |]

𝔱 "subst:⧺" [| subst (𝓈intro 1)               [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0 |] |]
𝔱 "subst:⧺" [| subst (null ⧺ 𝓈intro 1 ⧺ null) [ulcd| λ → 0 |] |] [| Some [ulcd| λ → 0 |] |]

𝔱 "subst:⧺" [| subst (𝓈intro 1)               [ulcd| λ → 1 |] |] [| Some [ulcd| λ → 2 |] |]
𝔱 "subst:⧺" [| subst (null ⧺ 𝓈intro 1 ⧺ null) [ulcd| λ → 1 |] |] [| Some [ulcd| λ → 2 |] |]

𝔱 "subst:⧺" [| subst (𝓈bind [ulcd| λ → 0 |]) [ulcd| λ → 1 |] |] 
            [| Some [ulcd| λ → λ → 0 |] |]
𝔱 "subst:⧺" [| subst (null ⧺ 𝓈bind [ulcd| λ → 0 |] ⧺ null) [ulcd| λ → 1 |] |] 
            [| Some [ulcd| λ → λ → 0 |] |]

𝔱 "subst:⧺" [| subst (𝓈intro 2) [ulcd| λ → 1 |] |]            [| Some [ulcd| λ → 3 |] |]
𝔱 "subst:⧺" [| subst (𝓈intro 1 ⧺ 𝓈intro 1) [ulcd| λ → 1 |] |] [| Some [ulcd| λ → 3 |] |]

𝔱 "subst:⧺" [| subst (𝓈bind [ulcd| λ → 0 |]) [ulcd| λ → 1 |] |] 
            [| Some [ulcd| λ → λ → 0 |] |]
𝔱 "subst:⧺" [| subst (𝓈shift 1 (𝓈bind [ulcd| λ → 0 |]) ⧺ 𝓈intro 1) [ulcd| λ → 1 |] |] 
            [| Some [ulcd| λ → λ → 0 |] |]

𝔱 "subst:⧺" [| subst (𝓈intro 1 ⧺ 𝓈bind [ulcd| 1 |]) [ulcd| 0 (λ → 2) |] |] 
            [| Some [ulcd| 2 (λ → 2) |] |]
𝔱 "subst:⧺" [| subst (𝓈shift 1 (𝓈bind [ulcd| 1 |]) ⧺ 𝓈intro 1) [ulcd| 0 (λ → 2) |] |] 
            [| Some [ulcd| 2 (λ → 2) |] |]

𝔱 "subst:⧺" [| subst (𝓈intro 1) *$ subst (𝓈shift 1 null) [ulcd| 0 |] |]
            [| subst (𝓈intro 1 ⧺ 𝓈shift 1 null) [ulcd| 0 |] |]

𝔱 "subst:⧺" [| subst (𝓈bind [ulcd| 1 |]) *$ subst (𝓈shift 1 (𝓈intro 1)) [ulcd| 0 |] |]
            [| subst (𝓈bind [ulcd| 1 |] ⧺ 𝓈shift 1 (𝓈intro 1)) [ulcd| 0 |] |]

𝔱 "subst:⧺" [| subst (𝓈shift 1 (𝓈bind [ulcd| 1 |])) *$ subst (𝓈shift 1 null) [ulcd| 1 |] |]
            [| subst (𝓈shift 1 (𝓈bind [ulcd| 1 |]) ⧺ 𝓈shift 1 null) [ulcd| 1 |] |]

𝔱 "subst:⧺" [| subst (𝓈shift 1 (𝓈bind [ulcd| 3 |]) ⧺ null) [ulcd| 0 |] |]
            [| subst (𝓈shift 1 (𝓈bind [ulcd| 3 |])) [ulcd| 0 |] |]

𝔱 "subst:⧺" [| (null 
                ⧺
                (DSubst (neg 1) 1 $ single $ Trm_DSE (neg 1) $ const $ return [ulcd| 0 |]))
            |]
            [| (DSubst (neg 1) 1 $ single $ Trm_DSE 0 $ const $ return [ulcd| -1 |])
            |]
𝔱 "subst:⧺" [| subst 
                 (DSubst (neg 1) 1 $ single $ Trm_DSE 0 $ const $ return [ulcd| -1 |])
                 [ulcd| -1 |] 
            |]
            [| subst 
                 (DSubst (neg 1) 1 $ single $ Trm_DSE (neg 1) $ const $ return [ulcd| 0 |])
                 [ulcd| -1 |]
            |]
𝔱 "subst:⧺" [| subst (𝓈intro 1) [ulcd| -1 |] |]
            [| Some [ulcd| 0 |] |]
𝔱 "subst:⧺" [| subst 
                 (DSubst 0 1 $ single $ Trm_DSE 1 $ const $ return [ulcd| -1 |])
                 [ulcd| 0 |] 
            |]
            [| subst 
                 (DSubst 0 1 $ single $ Trm_DSE 0 $ const $ return [ulcd| 0 |])
                 [ulcd| 0 |]
            |]
𝔱 "subst:⧺" [| subst 
                 (DSubst (neg 1) 1 $ single $ Trm_DSE 0 $ const $ return [ulcd| -1 |])
                 [ulcd| λ → 0 |] 
            |]
            [| subst 
                 (DSubst (neg 1) 1 $ single $ Trm_DSE (neg 1) $ const $ return [ulcd| 0 |])
                 [ulcd| λ → 0 |]
            |]

                  

-- fuzzing --

𝔣 "zzz:subst:refl:hom" 100 
  [| do e ← randSml @ULCDExpR
        return $ e
  |]
  [| \ e → 
       subst null e ≡ Some e
  |]

𝔣 "zzz:subst:refl/shift:hom" 100
  [| do i ← randSml @ℤ64
        e ← randSml @ULCDExpR
        return $ i :* e
  |]
  [| \ (i :* e) → subst (𝓈shift i null) e ≡ Some e 
  |]

𝔣 "zzz:subst:bind" 100
  [| do e₁ ← randSml @ULCDExpR
        e₂ ← randSml @ULCDExpR
        return $ e₁ :* e₂
  |]
  [| \ (e₁ :* e₂) → (subst (𝓈bind e₁) *$ subst (𝓈intro 1) e₂) ≡ Some e₂
  |]

𝔣 "zzz:subst:commute" 100
  [| do e₁ ← randSml @ULCDExpR
        e₂ ← randSml @ULCDExpR
        return $ e₁ :* e₂
  |]
  [| \ (e₁ :* e₂) → 
       (subst (𝓈intro 1) *$ subst (𝓈bind e₁) e₂)
       ≡ 
       (subst (𝓈shift 1 $ 𝓈bind e₁) *$ subst (𝓈intro 1) e₂)
  |]

𝔣 "zzz:subst:⧺:hom" 1000
  [| do 𝓈₁ ← rand @(DSubst ULCDExpR) 0 0
        𝓈₂ ← rand @(DSubst ULCDExpR) 1 1
        e ← rand @ULCDExpR 1 1
        return $ 𝓈₁ :* 𝓈₂ :* e
  |]
  [| \ (𝓈₁ :* 𝓈₂ :* e) → 
       subst (𝓈₁ ⧺ 𝓈₂) e ≡ (subst 𝓈₁ *$ subst 𝓈₂ e)
  |]

-- 𝔣 "zzz:ssubst:⧺:lrefl" 100 
--   [| do 𝓈 ← randSml @(DSubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈 :* e
--   |]
--   [| \ (𝓈 :* e) → 
--        subst (null ⧺ 𝓈) e ≡ subst 𝓈 e
--   |]

-- 𝔣 "zzz:ssubst:⧺:rrefl" 100 
--   [| do 𝓈 ← randSml @(SSubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈 :* e
--   |]
--   [| \ (𝓈 :* e) → 
--        ssubst (𝓈 ⧺ null) e ≡ ssubst 𝓈 e
--   |]
-- 
-- 𝔣 "zzz:ssubst:⧺:lrefl/shift" 100
--   [| do n ← randSml @ℕ64
--         𝓈 ← randSml @(SSubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ n :* 𝓈 :* e
--   |]
--   [| \ (n :* 𝓈 :* e) → ssubst (𝓈shift n null ⧺ 𝓈) e ≡ ssubst 𝓈 e 
--   |]
-- 
-- 𝔣 "zzz:ssubst:⧺:rrefl/shift" 100
--   [| do n ← randSml @ℕ64
--         𝓈 ← randSml @(SSubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ n :* 𝓈 :* e
--   |]
--   [| \ (n :* 𝓈 :* e) → ssubst (𝓈 ⧺ 𝓈shift n null) e ≡ ssubst 𝓈 e 
--   |]
-- 
-- 𝔣 "zzz:ssubst:⧺:trans" 100 
--   [| do 𝓈₁ ← randSml @(SSubst ULCDExpR)
--         𝓈₂ ← randSml @(SSubst ULCDExpR)
--         𝓈₃ ← randSml @(SSubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈₁ :* 𝓈₂ :* 𝓈₃ :* e
--   |]
--   [| \ (𝓈₁ :* 𝓈₂ :* 𝓈₃ :* e) → 
--        ssubst ((𝓈₁ ⧺ 𝓈₂) ⧺ 𝓈₃) e ≡ ssubst (𝓈₁ ⧺ (𝓈₂ ⧺ 𝓈₃)) e 
--   |]
-- 
-- 𝔣 "zzz:ssubst:shift/⧺:shift:dist" 100 
--   [| do n ← randSml @ℕ64
--         𝓈₁ ← randSml @(SSubst ULCDExpR)
--         𝓈₂ ← randSml @(SSubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ n :* 𝓈₁ :* 𝓈₂ :* e
--   |]
--   [| \ (n :* 𝓈₁ :* 𝓈₂ :* e) → 
--        ssubst (𝓈shift n (𝓈₁ ⧺ 𝓈₂)) e ≡ ssubst (𝓈shift n 𝓈₁ ⧺ 𝓈shift n 𝓈₂) e 
--   |]
-- 
-- 𝔣 "zzz:usubst:⧺:hom" 100 
--   [| do 𝓈₁ ← randSml @(USubst ULCDExpR)
--         𝓈₂ ← randSml @(USubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈₁ :* 𝓈₂ :* e
--   |]
--   [| \ (𝓈₁ :* 𝓈₂ :* e) → 
--        usubst (𝓈₁ ⧺ 𝓈₂) e ≡ usubst 𝓈₁ (usubst 𝓈₂ e)
--   |]
-- 
-- 𝔣 "zzz:usubst:⧺:lrefl" 100 
--   [| do 𝓈 ← randSml @(USubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈 :* e
--   |]
--   [| \ (𝓈 :* e) → 
--        usubst (null ⧺ 𝓈) e ≡ usubst 𝓈 e
--   |]
-- 
-- 𝔣 "zzz:usubst:⧺:rrefl" 100 
--   [| do 𝓈 ← randSml @(USubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈 :* e
--   |]
--   [| \ (𝓈 :* e) → 
--        usubst (𝓈 ⧺ null) e ≡ usubst 𝓈 e
--   |]
-- 
-- 𝔣 "zzz:usubst:⧺:trans" 100 
--   [| do 𝓈₁ ← randSml @(USubst ULCDExpR)
--         𝓈₂ ← randSml @(USubst ULCDExpR)
--         𝓈₃ ← randSml @(USubst ULCDExpR)
--         e ← randSml @ULCDExpR
--         return $ 𝓈₁ :* 𝓈₂ :* 𝓈₃ :* e
--   |]
--   [| \ (𝓈₁ :* 𝓈₂ :* 𝓈₃ :* e) → 
--        usubst ((𝓈₁ ⧺ 𝓈₂) ⧺ 𝓈₃) e ≡ usubst (𝓈₁ ⧺ (𝓈₂ ⧺ 𝓈₃)) e 
--   |]
-- 
-- 𝔣 "zzz:ssubst:open∘close" 100 
--   [| do randSml @ULCDExpR
--   |]
--   [| \ e → 
--        ssubst (𝓈open (var "z") ⧺ 𝓈close (var "z")) e ≡ e
--   |]
-- 
-- 𝔣 "zzz:ssubst:close∘open" 100 
--   [| do randSml @ULCDExpR
--   |]
--   [| \ e → 
--        ssubst (𝓈close (var "z") ⧺ 𝓈open (var "z")) e ≡ e
--   |]
buildTests

-- substyVar ∷ (Ord s,Monad m) ⇒ (𝕐 → e₂) → (ℤ64 → (𝕏 ⇰ ℤ64) → e₂ → e₂) → s → 𝕐 → SubstT s e₁ e₂ m e₂
-- substyVar evar eintro s y = do
--   σO ← lup s ^$ askL substEnvSubsL
--   case σO of
--     None → return $ evar y
--     Some σ → do
--       𝓋 ← askL substEnvViewL
--       case substVar σ y of
--         Var_DSE y' → return $ evar y'
--         Trm_DSE i' xis e → failEff $ eintro i' xis ^$ 𝓋 e




-- data Subst e = Subst
--   { substDShf ∷ ℕ64
--   , substNShf ∷ 𝕏 ⇰ ℕ64
--   , substDIro ∷ ℤ64
--   , substNIro ∷ 𝕏 ⇰ ℤ64
--   , substDMap ∷ 𝕍 (SubstElem e)
--   , substNMap ∷ 𝕏 ⇰ 𝕍 (SubstElem e)
--   , substMMap ∷ 𝕏 ⇰ e
--   } deriving (Eq,Ord,Show)
-- makeLenses ''Subst
-- 
-- substVar ∷ Subst e → 𝕐 → SubstElem e
-- substVar (Subst ρᴰ ρᴺ ιᴰ ιᴺ σᴰ σᴺ σᴹ) y = 
--   let ℯO = case y of
--         DVar i → tries
--           [ do guard $ i < intΩ64 ρᴰ
--                return $ Var_DSE $ DVar i
--           , do n ← natO64 $ i - intΩ64 ρᴰ
--                lup n σᴰ
--           ]
--         NVar i x → tries
--           [ do guard $ i < ifNone 0 (intΩ64 ^$ ρᴺ ⋕? x)
--                return $ Var_DSE $ NVar i x
--           , do n ← natO64 $ i - ifNone 0 (intΩ64 ^$ ρᴺ ⋕? x)
--                lup n *$ lup x σᴺ
--           ]
--         MVar x → do
--           e ← lup x σᴹ
--           return $ Trm_DSE 0 zero e
--   in case ℯO of
--     None → Var_DSE $ intro𝕐 ιᴰ ιᴺ y
--     Some ℯ → ℯ
-- 
-- data SubstEnv s e₁ e₂ = SubstEnv
--   { substEnvSubs ∷ s ⇰ Subst e₁
--   , substEnvView ∷ e₁ → 𝑂 e₂
--   }
-- makeLenses ''SubstEnv
-- 
-- newtype SubstT s e₁ e₂ (m ∷ ★ → ★) a = SubstT { unSubstT ∷ UContT (ReaderT (SubstEnv s e₁ e₂) (FailT m)) a }
--   deriving
--   ( Return,Bind,Functor,Monad
--   , MonadUCont
--   , MonadReader (SubstEnv s e₁ e₂)
--   , MonadFail
--   )
-- 
-- runSubstT ∷ (Monad m) ⇒ SubstEnv s e₁ e₂ → SubstT s e₁ e₂ m a → m (𝑂 a)
-- runSubstT γ = unFailT ∘ runReaderT γ ∘ evalUContT ∘ unSubstT
-- 
-- class Substy s e a where
--   substy ∷ ∀ e' m. a → SubstT s e' e m a
-- 
-- substyBdr ∷ (Ord s,ToIter s t,Monad m) ⇒ t → 𝕏 → SubstT s e₁ e₂ m ()
-- substyBdr ss x = do
--   umodifyEnvL substEnvSubsL $ compose $ mapOn (iter ss) $ mapOnKeyWith $ compose
--     [ alter substDShfL $ (+) 1
--     , alter substNShfL $ (+) $ x ↦ 1
--     ]
-- 
-- substyVar ∷ (Ord s,Monad m) ⇒ (𝕐 → e₂) → (ℤ64 → (𝕏 ⇰ ℤ64) → e₂ → e₂) → s → 𝕐 → SubstT s e₁ e₂ m e₂
-- substyVar evar eintro s y = do
--   σO ← lup s ^$ askL substEnvSubsL
--   case σO of
--     None → return $ evar y
--     Some σ → do
--       𝓋 ← askL substEnvViewL
--       case substVar σ y of
--         Var_DSE y' → return $ evar y'
--         Trm_DSE i' xis e → failEff $ eintro i' xis ^$ 𝓋 e
-- 
-- substAppend ∷ (Monad m) ⇒ (Subst a → b → m a) → Subst a → Subst b → m (Subst a)
-- substAppend 
--   esubst 
--   σ₂@(Subst ρᴰ₂ ρᴺ₂ ιᴰ₂ ιᴺ₂ σᴰ₂ σᴺ₂ σᴹ₂) 
--   σ₁@(Subst ρᴰ₁ ρᴺ₁ ιᴰ₁ ιᴺ₁ σᴰ₁ σᴺ₁ σᴹ₁) = do
--     let ρᴰ = ρᴰ₁ ⊓ ρᴰ₂
--         ρᴺ = ρᴺ₁ ⊓ ρᴺ₂
--         σᴰLogicalSize = natΩ64 $ joins
--           [ intΩ64 (csize σᴰ₁) + intΩ64 ρᴰ₁
--           , intΩ64 (csize σᴰ₂) + intΩ64 ρᴰ₂ - ιᴰ₁
--           ]
--         σᴰSize = σᴰLogicalSize - ρᴰ
--         σᴰOffset = ρᴰ₁ - ρᴰ
--         ιᴰ = ιᴰ₁ + ιᴰ₂
--     σᴰ ← exchange $ vecF σᴰSize $ \ n → do
--         if i < σᴰOffset
--         then return $ substVar σ₂ $ DVar $ int64 $ ρᴰ + n
--         else
--           case bvs₁ ⋕? (𝓍 - vsOffset₁) of
--             Some v → case v of
--               Inl 𝓎 → return $ 𝓈varsubst 𝓈₂ 𝓎
--               Inr (ρₑ :* e) → do
--                 𝓈 ← 𝓈combinesubst sub 𝓈₂ $ 𝓈intro ρₑ
--                 Inr ∘ (0 :*) ^$ sub 𝓈 e
--             None → return $ 𝓈bvarsubst 𝓈₂ $ natΩ64 $ intΩ64 (ρ + 𝓍) + ι₁
--      
--     σᴹ₁' ← mapMOn σᴹ₁ $ esubst σ₂
--     let σᴹ = σᴹ₁' ⩌ σᴹ₂
--     return $ Subst _ _ _ _ _ _ σᴹ₁'
-- 
-- 
-- 𝓈rnams ∷ 𝕏 ⇰ 𝕏 → Subst e
-- 𝓈rnams xxs = 
--   let n = count xxs
--       ℯs = vecC $ map (Var_DSE ∘ DVar ∘ intΩ64) $ upToC n
--       xℯs = map (single ∘ Var_DSE ∘ NVar 0) xxs
--   in Subst 0 null 0 null ℯs xℯs null
-- 
-- -- 𝓈dren ∷ 𝕏 → Subst e
-- -- 𝓈dren x = 
-- --   let ℯ = Var_DSE $ DVar 0
-- --   in Subst 0 null 0 null (single ℯ) (x ↦ single ℯ) null
-- -- 
-- -- 𝓈repl ∷ 𝕏 → e → Subst e
-- -- 𝓈repl x e = 
-- --   let ℯ = Trm_DSE 1 (x ↦ 1) e
-- --   in Subst 0 null 0 null (single ℯ) (x ↦ single ℯ) null
-- 
-- 𝓈metas ∷ 𝕏 ⇰ e → Subst e
-- 𝓈metas = Subst 0 null 0 null null null

-- -- data Subst s a m = Subst
-- --   { substBdr ∷ s ⇰ 𝕏 ⇰ 𝕏
-- --   , substVar ∷ s ⇰ 𝕐 ⇰ 𝕐 ∨ FailT m a
-- --   }
-- -- makeLenses ''Subst
-- -- 
-- -- data SubstEnv s a b m = SubstEnv
-- --   { substEnvFresh ∷ 𝑂 (m ℕ64)
-- --   , substEnvView  ∷ a → 𝑂 b
-- --   , substEnvSubst ∷ Subst s a m
-- --   }
-- -- makeLenses ''SubstEnv
-- -- 
-- -- newtype SubstT s e₁ e₂ m a = SubstM { unSubstM ∷ UContT (ReaderT (SubstEnv s e₁ e₂ m) (FailT m)) a }
-- --   deriving
-- --   ( Return,Bind,Functor,Monad
-- --   , MonadFail
-- --   , MonadReader (SubstEnv s e₁ e₂ m)
-- --   , MonadUCont
-- --   )
-- -- 
-- -- instance Transformer (SubstT s e₁ e₂) where lift = SubstM ∘ lift ∘ lift ∘ lift
-- -- 
-- -- runSubstT ∷ (Return m) ⇒ SubstEnv s e₁ e₂ m → SubstT s e₁ e₂ m a → m (𝑂 a)
-- -- runSubstT γ = unFailT ∘ runReaderT γ ∘ evalUContT ∘ unSubstM
-- -- 
-- -- class Substy s e a | a→s,a→e where
-- --   substy ∷ ∀ e' m. (Monad m) ⇒ a → SubstT s e' e m a
-- -- 
-- -- subst ∷ (Substy s e a,Monad m) ⇒ Subst s e m → a → m (𝑂 a)
-- -- subst γ = runSubstT (SubstEnv None return γ) ∘ substy
-- -- 
-- -- freshen ∷ (Substy s e a,Monad m) ⇒ m ℕ64 → a → m (𝑂 a)
-- -- freshen 𝑓M = runSubstT (SubstEnv (Some 𝑓M) return null) ∘ substy
-- -- 
-- -- instance Null (Subst s a m) where
-- --   null = Subst null null
-- -- instance (Ord s,Monad m,Substy s a a) ⇒ Append (Subst s a m) where
-- --   𝓈₁@(Subst sρ₁ sγ₁) ⧺ Subst sρ₂ sγ₂=
-- --     let sρ₂' = dmapOnWithKey sρ₂ $ \ s → map $ \ x →
-- --           ifNone x $ do
-- --             ρ ← sρ₁ ⋕? s
-- --             ρ ⋕? x
-- --         sγ₂' = dmapOnWithKey sγ₂ $ \ s → map $ \case
-- --           Inl x → ifNone (Inl x) $ do
-- --             γ ← sγ₁ ⋕? s
-- --             γ ⋕? x
-- --           Inr eM → Inr $ do
-- --             e ← eM
-- --             FailT $ subst 𝓈₁ e
-- --         sρ = unionWith (⩌) sρ₂' sρ₁
-- --         sγ = unionWith (⩌) sγ₂' sγ₁
-- --     in Subst sρ sγ 
-- -- instance (Ord s,Monad m,Substy s a a) ⇒ Monoid (Subst s a m)
-- -- 
-- -- 𝓈rescope ∷ (Ord s) ⇒ s ⇰ 𝕏 ⇰ 𝕏 → Subst s a m
-- -- 𝓈rescope ρ= Subst ρ null
-- -- 
-- -- 𝓈rename ∷ (Ord s) ⇒ s ⇰ 𝕐 ⇰ 𝕐 → Subst s a m
-- -- 𝓈rename sxx = Subst null $ map (map Inl) sxx
-- -- 
-- -- 𝓈bindM ∷ (Ord s,Monad m) ⇒ s ⇰ 𝕐 ⇰ m a → Subst s a m
-- -- 𝓈bindM sxeM = Subst null $ map (map $ Inr ∘ lift) sxeM
-- -- 
-- -- 𝓈bind ∷ (Ord s,Monad m) ⇒ s ⇰ 𝕐 ⇰ a → Subst s a m
-- -- 𝓈bind = 𝓈bindM ∘ mapp return
-- -- 
-- -- substyVar ∷ (Ord s,Monad m) ⇒ (𝕐 → e₂) → s → 𝕐 → SubstT s e₁ e₂ m e₂
-- -- substyVar v s x = mjoin $ tries
-- --   [ do SubstEnv _ 𝓋 (Subst _ sγ) ← ask
-- --        γ ← failEff $ sγ ⋕? s
-- --        xeM ← failEff $ γ ⋕? x
-- --        return $ case xeM of
-- --          Inl x' → return $ v x'
-- --          Inr eM → do
-- --            e ← failEff *$ lift $ unFailT eM
-- --            failEff $ 𝓋 e
-- --   , return $ return $ v x
-- --   ]
-- -- 
-- -- substyBdr ∷ (Ord s,Monad m,ToIter s t) ⇒ t → 𝕏 → SubstT s e₁ e₂ m 𝕏
-- -- substyBdr ss x = do
-- --   sρ ← askL $ substBdrL ⊚ substEnvSubstL
-- --   𝑓M ← askL substEnvFreshL
-- --   xO ← tries $ concat
-- --     -- first see if we are rescoping
-- --     [ mapOn (iter ss) $ \ s → do
-- --         do ρ ← failEff $ sρ ⋕? s
-- --            x' ← failEff $ ρ ⋕? x
-- --            return $ Some x'
-- --     -- next see if we are freshening binders
-- --     , single $ do
-- --         n ← lift *$ failEff 𝑓M
-- --         let x' = 𝕏 (Some n) $ 𝕩name x
-- --         return $ Some x'
-- --     -- just leave the binder alone...
-- --     , single $ return None
-- --     ]
-- --   x' ← case xO of
-- --     Some x' → do
-- --       eachOn ss $ \ s →
-- --         umodifyEnvL (keyL s ⊚ substVarL ⊚ substEnvSubstL) $ \ 𝓈O →
-- --           Some $ (svar𝕏 x ↦ Inl (svar𝕏 x')) ⩌ ifNone null 𝓈O
-- --       return x'
-- --     None → return x
-- --   eachOn ss $ \ s →
-- --     umodifyEnvL (keyL s ⊚ substVarL ⊚ substEnvSubstL) $ map $ delete $ svar𝕏 x'
-- --   return x'
-- -- 
-- -- substyFrame ∷ (Monad m) ⇒ (e₂ → 𝑂 e₃) → SubstT s e₁ e₃ m a → SubstT s e₁ e₂ m a
-- -- substyFrame 𝓋 xM = do
-- --   SubstEnv 𝑓M 𝓋' 𝓈 ← ask
-- --   failEff *$ lift $ runSubstT (SubstEnv 𝑓M (𝓋 *∘ 𝓋') 𝓈) xM

---------------
-- FREE VARS --
---------------

newtype FreevM s a = FreevM { unFreevM ∷ UContT (RWS (s ⇰ 𝕏 ⇰ ℤ64) (s ⇰ 𝑃 𝕐) ()) a }
  deriving
  ( Return,Bind,Functor,Monad
  , MonadReader (s ⇰ 𝕏 ⇰ ℤ64)
  , MonadWriter (s ⇰ 𝑃 𝕐)
  , MonadUCont
  )

runFreevM ∷ (s ⇰ 𝕏 ⇰ ℤ64) → FreevM s a → (s ⇰ 𝑃 𝕐) ∧ a
runFreevM γ = mapFst snd ∘ runRWS γ () ∘ evalUContT ∘ unFreevM

evalFreevM ∷ FreevM s a → a
evalFreevM = snd ∘ runFreevM null

class Freevy s a | a → s where
  freevy ∷ a → FreevM s ()

freevyBdr ∷ (Ord s,ToIter s t) ⇒ t → 𝕏 → FreevM s ()
freevyBdr ss x = umodifyEnv $ (⧺) $ concat $ mapOn (iter ss) $ \ s → s ↦ x ↦ 1

freevyVar ∷ (Ord s) ⇒ s → 𝕐 → FreevM s ()
freevyVar s y = do
  𝑠 ← ask
  case y of
    NVar n x → do
      case lup x *$ lup s 𝑠 of
        None → tell $ (↦) s $ single $ NVar n x
        Some n' → whenZ (n ≥ n') $ tell $ (↦) s $ single $ NVar (n - n') x
    DVar n → do
      case lup s 𝑠 of
        None → tell $ (↦) s $ single $ DVar n
        Some xns → do
          let n' = sum $ values xns
          whenZ (n ≥ n') $ tell $ (↦) s $ single $ DVar $ n - n'
    MVar x → tell $ (↦) s $ single $ MVar x

fvs ∷ (Ord s,Freevy s a) ⇒ a → s ⇰ 𝑃 𝕐
fvs = evalFreevM ∘ retOut ∘ freevy

sfvs ∷ (Ord s,Freevy s a) ⇒ s → a → 𝑃 𝕐
sfvs s = ifNone bot ∘ lup s ∘ fvs



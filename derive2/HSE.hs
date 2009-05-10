{-# LANGUAGE DeriveDataTypeable #-}

module HSE(module HSE, module Language.Haskell.Exts) where

import Language.Haskell.Exts hiding (List, App, String, Int)
import qualified Language.Haskell.Exts as H
import Data.Data
import Data.Generics.PlateData
import Data.Maybe
import Unsafe.Coerce
import Control.Monad.State


---------------------------------------------------------------------
-- EXAMPLES

sl = SrcLoc "" 0 0

-- data List a = Nil | Cons a (List a)
dataTypeList :: Dat
dataTypeList = DataDecl sl DataType [] (Ident "List") [Ident "a"] [nil,cons] []
    where
        nil = QualConDecl sl [] [] $ ConDecl (Ident "Nil") []
        cons = QualConDecl sl [] [] $ ConDecl (Ident "Cons")
            [UnBangedTy $ TyVar $ Ident "a", UnBangedTy $ TyApp (TyCon $ UnQual $ Ident "List") (TyVar $ Ident "a")]


-- data Input a = First | Second a a | Third a
dataTypeCtors :: Dat
dataTypeCtors = DataDecl sl DataType [] (Ident "Sample") [Ident "a"] [f "First" 0, f "Second" 2, f "Third" 1] []
    where f s n = QualConDecl sl [] [] $ ConDecl (Ident s) $ replicate n $ UnBangedTy $ TyVar $ Ident "a"


---------------------------------------------------------------------
-- UTILITIES

isUnknownDeclPragma UnknownDeclPragma{} = True
isUnknownDeclPragma _ = False


simplifyRes :: Res -> Res
simplifyRes = transformBi fExp
    where
        x ~= y = prettyPrint x == y
    
        fExp (H.App op (H.List xs))
            | op ~= "length" = Lit $ H.Int $ fromIntegral $ length xs
            | op ~= "head" = head xs
        fExp (InfixApp (Lit (H.Int i)) op (Lit (H.Int j)))
            | op ~= "-" = Lit $ H.Int $ i - j
            | op ~= ">" = Con $ UnQual $ Ident $ show $ i > j
        fExp (InfixApp x op y) | op ~= "`const`" = x
        fExp (H.App (H.App con x) y) | con ~= "const" = x
        fExp (Paren (Var x)) = Var x
        fExp (Paren (Lit x)) = Lit x
        fExp x = x


---------------------------------------------------------------------

showRes x = unlines $ map prettyPrint x

type Dat = Decl
type Ctr = QualConDecl
type Res = [Decl]


dataVars :: Dat -> [String]
dataVars (DataDecl _ _ _ _ x _ _) = map prettyPrint x

dataName :: Dat -> String
dataName (DataDecl _ _ _ x _ _ _) = prettyPrint x

dataCtors :: Dat -> [Ctr]
dataCtors (DataDecl _ _ _ _ _ x _) = x

ctorName :: Ctr -> String
ctorName (QualConDecl _ _ _ (ConDecl x _)) = prettyPrint x

ctorFields :: Ctr -> Int
ctorFields (QualConDecl _ _ _ (ConDecl _ x)) = length x




data Universe = UString String
              | UInt Integer
              | UApp String [Universe]
              | UList [Universe]
              | UIgnore
              deriving (Eq,Show,Data,Typeable)


toUniverse :: Data a => a -> Universe
toUniverse x
    | t == typeOf "" = UString $ coerce x
    | c == "[]" = UList $ fList x
    | t == typeOf sl = UIgnore
    | t == typeOf (1 :: Integer) = UInt $ coerce x
    | otherwise = UApp (showConstr $ toConstr x) (filter (/= UIgnore) $ gmapQ toUniverse x)
    where
        t = typeOf x
        c = show $ fst $ splitTyConApp t

        fList :: Data a => a -> [Universe]
        fList = gmapQl (++) [] $ \x -> if typeOf x == t then fList x else [toUniverse x]

fromUniverse :: Data a => Universe -> a
fromUniverse (UList xs) = res
    where res = f xs
          f [] = fromConstr $ readCon dat "[]"
          f (x:xs) = fromConstrB (g x (f xs `asTypeOf` res)) $ readCon dat "(:)"
          dat = dataTypeOf res
          typ = typeOf res
          
          g :: (Data a, Data b) => Universe -> a -> b
          g x xs = r2 where r2 = if typeOf r2 == typeOf xs then coerce xs else fromUniverse x

fromUniverse (UApp str args) = res
    where dat = dataTypeOf res
          res = evalState (fromConstrM f $ readCon dat str) args
          f :: Data a => State [Universe] a
          f = res where res = if typeOf (fromState res) == typeOf sl then return $ coerce sl else
                              do x:xs <- get; put xs; return $ fromUniverse x

fromUniverse (UString x) = coerce x

fromUniverse (UInt x) = coerce x

-- fromUniverse (UApp str args) = fromJust $ readConstr dat str
fromUniverse x = error $ show ("fromUniverse",x)


coerce x = fromMaybe (error "Error in coerce") $ cast x
readCon dat x = fromMaybe (error $ "Error in readCon, " ++ x) $ readConstr dat x
uni x = toUniverse x
fromState :: State a x -> x
fromState = undefined

-- | The core module of the Data.Derive system.  This module contains
-- the data types used for communication between the extractors and
-- the derivors.
module Language.Haskell.TH.Helper where

import Data.List
import Data.Char

import Language.Haskell.TH.Syntax
import Language.Haskell.TH.Data


-- * Template Haskell helper functions
--
-- These small short-named functions are intended to make the
-- construction of abstranct syntax trees less tedious.

-- | A simple clause, without where or guards.
sclause :: [Pat] -> Exp -> Clause
sclause pats body = Clause pats (NormalB body) []

-- | A default clause with N arguments.
defclause :: Int -> Exp -> Clause
defclause num = sclause (replicate num WildP)

-- | A simple Val clause
sval :: Pat -> Exp -> Dec
sval pat body = ValD pat (NormalB body) []


-- | The class used to overload lifting operations.  To reduce code
-- duplication, we overload the wrapped constructors (and everything
-- else, but that's irrelevant) to work both in patterns and
-- expressions.
class Valcon a where
      -- | Build an application node, with a name for a head and a
      -- provided list of arguments.
      lK :: String -> [a] -> a
      -- | Reference a named variable.
      vr :: String -> a
      -- | Lift a TH 'Lit'
      raw_lit :: Lit -> a
      -- | Tupling
      tup :: [a] -> a
      -- | Listing
      lst :: [a] -> a
instance Valcon Exp where
      lK nm@(x:_) args | isUpper x || x == ':' = foldl AppE (ConE (mkName nm)) args
      lK nm@(x:_) [a,b] | isOper x = InfixE (Just a) (VarE (mkName nm)) (Just b)
         where isOper c = isSymbol c || isPunctuation c
      lK nm       args = foldl AppE (VarE (mkName nm)) args
      vr = VarE . mkName
      raw_lit = LitE
      tup = TupE
      lst = ListE
instance Valcon Pat where
      lK = ConP . mkName
      vr = VarP . mkName
      raw_lit = LitP
      tup = TupP
      lst = ListP

-- | This class is used to overload literal construction based on the
-- type of the literal.
class LitC a where
      lit :: Valcon p => a -> p
instance LitC Integer where
      lit = raw_lit . IntegerL
instance LitC Char where
      lit = raw_lit . CharL
instance LitC a => LitC [a] where
      lit = lst . map lit
instance (LitC a, LitC b) => LitC (a,b) where
      lit (x,y) = tup [lit x, lit y]
instance (LitC a, LitC b, LitC c) => LitC (a,b,c) where
      lit (x,y,z) = tup [lit x, lit y, lit z]
instance LitC () where
      lit () = tup []

-- * Lift a constructor over a fixed number of arguments.

l0 :: Valcon a => String -> a
l1 :: Valcon a => String -> a -> a
l2 :: Valcon a => String -> a -> a -> a
l0 s     = lK s []
l1 s a   = lK s [a]
l2 s a b = lK s [a,b]

-- * Pre-lifted versions of common operations
true, false, nil :: Valcon a => a
true = l0 "True"
false = l0 "False"
nil = l0 "[]"

cons :: Valcon a => a -> a -> a
cons = l2 ":"

box, return' :: Exp -> Exp
box x = cons x nil
return' = l1 "return"

(==:), (&&:), (++:), (>>=:), (>>:), ap' :: Exp -> Exp -> Exp
(==:) = l2 "=="
(&&:) = l2 "&&"
(++:) = l2 "++"
(>>=:) = l2 ">>="
(>>:) = l2 ">>"
ap' = l2 "ap"

case' :: Exp -> [(Pat, Exp)] -> Exp
case' exp alts = CaseE exp [ Match x (NormalB y) [] | (x,y) <- alts ]
(->:) :: String -> Exp -> Exp
(->:) nm bdy = LamE [vr nm] bdy

-- | Build a chain of and-expressions.
and' :: [Exp] -> Exp
and' = foldr (&&:) true

-- | Build a chain of concat-expressions.
concat' :: [Exp] -> Exp
concat' = foldr (++:) nil

-- | Build a chain of monadic actions.
sequ' :: [Exp] -> Exp
sequ' = foldr (>>:) (return' (lit ()))

-- | K-way liftM
liftmk :: Exp -> [Exp] -> Exp
liftmk hd args = foldl ap' (return' hd) args

-- | Build an instance of a class for a data type, using the heuristic
-- that the type is itself required on all type arguments.
simple_instance :: String -> DataDef -> [Dec] -> [Dec]
simple_instance cls (DataDef name arity _) defs = [InstanceD ctx hed defs]
    where
        vars = map (VarT . mkName . ('t':) . show) [1..arity]
        hed = ConT (mkName cls) `AppT` (foldl1 AppT (ConT (mkName name) : vars))
        ctx = map (ConT (mkName cls) `AppT`) vars

-- | Build an instance of a class for a data type, using the class at the given types
generic_instance :: String -> DataDef -> [Type] -> [Dec] -> [Dec]
generic_instance cls (DataDef name arity _) ctxTypes defs = [InstanceD ctx hed defs]
    where
        vars = map (VarT . mkName . ('t':) . show) [1..arity]
        hed = ConT (mkName cls) `AppT` (foldl1 AppT (ConT (mkName name) : vars))
        ctx = map (ConT (mkName cls) `AppT`) ctxTypes

-- | Build a fundecl with a string name
funN :: String -> [Clause] -> Dec
funN nam claus = FunD (mkName nam) claus

-- | Make a list of variables, one for each argument to a constructor
ctv :: Valcon a => CtorDef -> Char -> [a]
ctv ctor c = map (vr . (c:) . show) [1 .. ctorArity ctor]

-- | Make a simple pattern to bind a constructor
ctp :: Valcon a => CtorDef -> Char -> a
ctp ctor c = lK (ctorName ctor) (ctv ctor c)

-- | Reference the constructor itself
ctc :: Valcon a => CtorDef -> a
ctc = l0 . ctorName

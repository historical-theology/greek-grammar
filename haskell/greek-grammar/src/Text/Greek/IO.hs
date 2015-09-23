module Text.Greek.IO where

import Control.Lens
import Data.Either
import Text.Greek.FileReference
import Text.Greek.Source.All
import Text.Parsec.Error (ParseError)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Text.Greek.Script.Letter as Letter
import qualified Text.Greek.Script.Mark as Mark
import qualified Text.Greek.Script.Unicode as U
import qualified Text.Greek.Script.Unit as U

handleAll :: IO [Work [BasicWord [U.Unit (Letter.Case, (Letter.Letter, Letter.IsLast)) Mark.AllPair]]]
handleAll = loadAll >>= handleEither
  >>= handleListEither . workToUnitChar
  >>= handleListEither . workToUnitUnicode
  >>= handleListEither . parseFinalForms . workToCaseLetterFinal
  >>= handleListEither . toMarkAll

workToUnitChar ::        [Work [BasicWord (T.Text, FileReference)]]
  -> [Either U.UnitError (Work [BasicWord [U.UnitChar]])]
workToUnitChar = fmap $ (workContent . traverse . basicWordSurface) U.toUnitChar

workToUnitUnicode ::        [Work [BasicWord [U.UnitChar]]]
  -> [Either U.UnicodeError (Work [BasicWord [U.UnitUnicode]])]
workToUnitUnicode = fmap $ (workContent . traverse . basicWordSurface . traverse) U.toUnitUnicode

workToCaseLetterFinal
  :: [Work [BasicWord [U.UnitMarkList U.UnicodeLetter            U.UnicodeMark]]]
  -> [Work [BasicWord [U.UnitMarkList (Letter.Case, Letter.LetterFinal) U.UnicodeMark]]]
workToCaseLetterFinal = over (traverse . workContent . traverse . basicWordSurface . traverse . U.unitLetter . _1) Letter.toCaseLetterFinal

parseFinalForms
  ::   [Work [BasicWord [U.UnitMarkList (Letter.Case, Letter.LetterFinal)             U.UnicodeMark]]]
  -> [Either
       ParseError
       (Work [BasicWord [U.UnitMarkList (Letter.Case, (Letter.Letter, Letter.IsLast)) U.UnicodeMark]])]
parseFinalForms = fmap $ (workContent . traverse . basicWordSurface) (Letter.parseFinals (^. U.unitLetter . _2 . fileCharReferenceLine) (U.unitLetter . _1 . _2))

toMarkAll
  ::   [Work [BasicWord [U.UnitMarkList (Letter.Case, (Letter.Letter, Letter.IsLast)) U.UnicodeMark]]]
  -> [Either
       Mark.Error
       (Work [BasicWord [U.Unit         (Letter.Case, (Letter.Letter, Letter.IsLast)) Mark.AllPair]])]
toMarkAll = fmap $ (workContent . traverse . basicWordSurface . traverse . U.unitMarks) Mark.toAllPair

printErrors :: (Show e, Foldable t) => t e -> IO a
printErrors es = do
  mapM_ (T.putStrLn . T.pack . show) es
  fail "failure"

handleEither :: (Show e, Foldable t) => Either (t e) x -> IO x
handleEither (Left es) = printErrors es
handleEither (Right x) = return x

handleListEither :: (Show e) => [Either e x] -> IO [x]
handleListEither eithers = case errors of
  _ : _ -> printErrors errors
  [] -> return results
  where
    (errors, results) = partitionEithers eithers

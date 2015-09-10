{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Text.Greek.Source.Sblgnt where

import Prelude hiding ((*), (+), getLine, Word)
import Control.Lens hiding (element)
import Data.Maybe
import Data.Text (Text)
import Text.Greek.Utility
import Text.Greek.Xml
import Text.Parsec.Combinator
import Text.Parsec.Error (ParseError)
import Text.Parsec.Pos (SourcePos)
import Text.Parsec.Prim
import qualified Data.XML.Types as X
import qualified Text.Parsec.Pos as P

type Event = FileReference * BasicEvent XmlLocalName X.Content [XmlAttribute]

type EventParser = ParsecT [Event] () Identity
type AttributeParser = ParsecT [XmlAttribute] () Identity

readSblgntEvents :: FilePath -> IO ([SblgntError] + Sblgnt)
readSblgntEvents p = fmap (sblgntTransform p) . readEvents $ p

sblgntTransform
  :: FilePath
  -> [XmlInternalError] + [FileReference * X.Event]
  -> [SblgntError] + Sblgnt
sblgntTransform p x
  =   liftErrors SblgntErrorXmlInternal x
  >>. dropComments
  >>. trimContent _2
  >>= liftErrors SblgntErrorXml . toBasicEvents
  >>= tryOverAll (_2 . _BasicEventBeginElement . _1) tryDropNamespace (errorContext SblgntErrorUnexpectedNamespace _1)
  >>= tryOverAll (_2 . _BasicEventEndElement) tryDropNamespace (errorContext SblgntErrorUnexpectedNamespace _1)
  >>= over _Left (pure . SblgntErrorEventParse) . parseEvents p

data SblgntError
  = SblgntErrorXmlInternal XmlInternalError
  | SblgntErrorXml (XmlError FileReference)
  | SblgntErrorUnexpectedNamespace FileReference X.Name
  | SblgntErrorEventParse ParseError
  deriving (Show)

parseEvent :: Stream s m Event => (Event -> Maybe a) -> ParsecT s u m a
parseEvent = tokenPrim show updateEventPos

parseAttribute :: Stream s m XmlAttribute => (XmlAttribute -> Maybe a) -> ParsecT s u m a
parseAttribute = tokenPrim show (const . const)

satisfy :: Stream s m Event => (Event -> Bool) -> ParsecT s u m Event
satisfy p = tokenPrim show updateEventPos testEvent
  where testEvent x = if p x then Just x else Nothing

updateEventPos :: SourcePos -> (FileReference, t) -> s -> SourcePos
updateEventPos p (r, _) _ = flip P.setSourceColumn column . flip P.setSourceLine line $ p
  where
    beginPos = fileReferenceBegin r
    line = getLine . lineReferenceLine $ beginPos
    column = getColumn . lineReferenceColumn $ beginPos

emptyAttributes :: AttributeParser ()
emptyAttributes = fmap (const ()) eof

simpleAttributeParser :: Text -> AttributeParser Text
simpleAttributeParser n = parseAttribute parseSimple
  where
    parseSimple ((X.Name n' Nothing Nothing), [X.ContentText t]) | n == n' = Just t
    parseSimple _ = Nothing

xmlLangAttributeParser :: Text -> AttributeParser Text
xmlLangAttributeParser v = parseAttribute parseSimple <?> "Invalid xml:lang attribute"
  where
    parseSimple ((X.Name "lang" (Just ns) (Just p)), [X.ContentText t]) | ns == xmlNamespace, p == xmlNamespacePrefix, t == v = Just t
    parseSimple _ = Nothing

newtype Target = Target Text deriving Show

hrefAttributeParser :: AttributeParser Target
hrefAttributeParser = Target <$> simpleAttributeParser "href"

begin :: Stream s m Event => XmlLocalName -> AttributeParser a -> ParsecT s u m a
begin n ap = parseEvent parseBeginEvent
  where
    parseBeginEvent (_, (BasicEventBeginElement n' a)) | n == n' = case parse ap "" a of
      Left _ -> Nothing
      Right x -> Just x
    parseBeginEvent _ = Nothing

beginSimple :: Stream s m Event => XmlLocalName -> ParsecT s u m ()
beginSimple n = begin n emptyAttributes

end :: Stream s m Event => XmlLocalName -> ParsecT s u m Event
end n = satisfy isEnd
  where
    isEnd :: Event -> Bool
    isEnd (_, (BasicEventEndElement n')) | n == n' = True
    isEnd _ = False

emptyElement :: XmlLocalName -> EventParser ()
emptyElement n = beginSimple n <* end n

elementOpen :: Stream s m Event => XmlLocalName -> ParsecT s u m [Event]
elementOpen n = beginSimple n *> manyTill anyEvent (try (end n))

element :: XmlLocalName -> AttributeParser a -> EventParser b -> (a -> b -> c) -> EventParser c
element n ap cp f = go
  where
    go = do
      a <- begin n ap
      b <- cp
      _ <- end n
      return $ f a b

elementSimple :: XmlLocalName -> EventParser a -> EventParser a
elementSimple n p = beginSimple n *> p <* end n

contentReferenceParser :: EventParser (FileReference, Text)
contentReferenceParser = parseEvent getContent
  where
    getContent :: Event -> Maybe (FileReference, Text)
    getContent (r, BasicEventContent (X.ContentText t)) = Just (r, t)
    getContent _ = Nothing

contentParser :: EventParser Text
contentParser = fmap snd contentReferenceParser

elementContent :: XmlLocalName -> EventParser Text
elementContent = flip elementSimple contentParser

elementContentReference :: XmlLocalName -> EventParser (FileReference, Text)
elementContentReference = flip elementSimple contentReferenceParser

newtype Paragraph = Paragraph Text deriving Show

paragraphParser :: EventParser c -> EventParser c
paragraphParser p = elementSimple "p" p

paragraphSimpleParser :: EventParser Paragraph
paragraphSimpleParser = fmap Paragraph (paragraphParser contentParser)

newtype Title = Title [Paragraph] deriving Show

titleParser :: EventParser Title
titleParser = fmap Title $ elementSimple "title" (many paragraphSimpleParser)

data Link = Link { linkHref :: Target, linkContent :: Text } deriving Show

newtype Content = Content Text deriving Show
data ParagraphLink
  = ParagraphLinkContent Content
  | ParagraphLinkLink Link
  deriving Show

linkParser :: EventParser Link
linkParser = element "a" hrefAttributeParser contentParser Link

paragraphLinkParser :: EventParser ParagraphLink
paragraphLinkParser = content <|> link
  where
    content = fmap (ParagraphLinkContent . Content) contentParser
    link = fmap ParagraphLinkLink linkParser

newtype License = License [ParagraphLink] deriving Show
licenseParser :: EventParser License
licenseParser = fmap License $ elementSimple "license" (paragraphParser (many paragraphLinkParser))

data Verse = Verse { verseId :: Text, verseText :: Text } deriving Show

verseParser :: EventParser Verse
verseParser = element "verse-number" (simpleAttributeParser "id") contentParser Verse

newtype MarkEnd = MarkEnd Text deriving Show

markEndParser :: EventParser MarkEnd
markEndParser = element "mark-end" (xmlLangAttributeParser "en") contentParser (const MarkEnd)

data Word = Word
  { wordSurface :: Text
  , wordFileReference :: FileReference
  , wordPrefix :: Maybe Text
  , wordSuffix :: Text
  } deriving Show

wordParser :: EventParser Word
wordParser = do
  prefix <- optionMaybe (elementContent "prefix")
  (r, surface) <- elementContentReference "w"
  suffix <- elementContent "suffix"
  return $ Word surface r prefix suffix

data Item = ItemVerse Verse | ItemWord Word deriving Show

itemParser :: EventParser Item
itemParser = fmap ItemVerse verseParser <|> fmap ItemWord wordParser

data BookParagraph = BookParagraphContent [Item] | BookParagraphMarkEnd MarkEnd deriving Show

bookParagraphParser :: EventParser (Maybe BookParagraph)
bookParagraphParser
  =   try (fmap (Just . BookParagraphContent) (paragraphParser (many1 itemParser)))
  <|> fmap (Just . BookParagraphMarkEnd) markEndParser
  <|> fmap (const Nothing) (emptyElement "p")
  <?> "Unknown book paragraph item"

data Book = Book
  { bookId :: Text
  , bookTitle :: Text
  , bookParagraphs :: [BookParagraph]
  }
  deriving Show

bookParser :: EventParser Book
bookParser = element "book" (simpleAttributeParser "id") bookContentParser (\i (t,p) -> Book i t p)
  where
    bookContentParser = do
      title <- elementContent "title"
      paragraphs <- many1 bookParagraphParser
      return (title, catMaybes paragraphs)

anyEvent :: Stream s m Event => ParsecT s u m Event
anyEvent = satisfy (const True)

data Sblgnt = Sblgnt { sblgntTitle :: Title, sblgntLicense :: License, sblgntBooks :: [Book] } deriving Show

sblgntParser :: EventParser Sblgnt
sblgntParser = elementSimple "sblgnt" sblgntContent
  where
    sblgntContent = do
      title <- titleParser
      license <- licenseParser
      books <- many bookParser
      return $ Sblgnt title license books

parseEvents :: FilePath -> [Event] -> ParseError + Sblgnt
parseEvents = parse sblgntParser

{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module Text.Greek.Source.Sblgnt where

import Prelude hiding ((*), (+), log, FilePath)
import Control.Lens
import Text.Greek.Utility
import Text.Greek.Xml
import qualified Prelude as X (FilePath)

type FinalXmlEvent
  = XmlBeginElement * ElementAll * XmlAttributes
  + XmlEndElement * ElementAll
  + XmlContent

newtype AElement = AElement () deriving (Eq, Ord, Show)
newtype BookElement = BookElement () deriving (Eq, Ord, Show)
newtype LicenseElement = LicenseElement () deriving (Eq, Ord, Show)
newtype MarkEndElement = MarkEndElement () deriving (Eq, Ord, Show)
newtype PElement = PElement () deriving (Eq, Ord, Show)
newtype PrefixElement = PrefixElement () deriving (Eq, Ord, Show)
newtype SblgntElement = SblgntElement () deriving (Eq, Ord, Show)
newtype SuffixElement = SuffixElement () deriving (Eq, Ord, Show)
newtype TitleElement = TitleElement () deriving (Eq, Ord, Show)
newtype VerseNumberElement = VerseNumberElement () deriving (Eq, Ord, Show)
newtype WElement = WElement () deriving (Eq, Ord, Show)

type ElementAll
  = SblgntElement
  + AElement
  + BookElement
  + LicenseElement
  + MarkEndElement
  + PElement
  + PrefixElement
  + SuffixElement
  + TitleElement
  + VerseNumberElement
  + WElement

toElementAll :: XmlLocalName -> XmlLocalName + ElementAll
toElementAll (XmlLocalName "sblgnt"      ) = Right . sum1   $ SblgntElement ()
toElementAll (XmlLocalName "a"           ) = Right . sum2   $ AElement ()
toElementAll (XmlLocalName "book"        ) = Right . sum3   $ BookElement ()
toElementAll (XmlLocalName "license"     ) = Right . sum4   $ LicenseElement ()
toElementAll (XmlLocalName "mark-end"    ) = Right . sum5   $ MarkEndElement ()
toElementAll (XmlLocalName "p"           ) = Right . sum6   $ PElement ()
toElementAll (XmlLocalName "prefix"      ) = Right . sum7   $ PrefixElement ()
toElementAll (XmlLocalName "suffix"      ) = Right . sum8   $ SuffixElement ()
toElementAll (XmlLocalName "title"       ) = Right . sum9   $ TitleElement ()
toElementAll (XmlLocalName "verse-number") = Right . sum10  $ VerseNumberElement ()
toElementAll (XmlLocalName "w"           ) = Right . sum11e $ WElement ()
toElementAll t                             = Left t



readSblgntEvents :: X.FilePath -> IO ([ErrorMessage] + [FileReference * FinalXmlEvent + Sblgnt * [FileReference * FinalXmlEvent]])
readSblgntEvents = fmap (>>= sblgntTransform) . readEvents

sblgntTransform
  :: [FileReference * XmlEventAll]
  -> [ErrorMessage] + [FileReference * FinalXmlEvent + Sblgnt * [FileReference * FinalXmlEvent]]
sblgntTransform x = return x
  >>. trimContent
  >>= removeUnusedXmlEvents
  >>= removeBeginElementNamespace
  >>= removeEndElementNamespace
  >>= useBeginElementType
  >>= useEndElementType
  >>= extractSblgnt
  -- >>= topLevelSblgnt

type XmlUnused
  = XmlCDATA
  + XmlBeginDoctype * XmlDoctypeName * (None + XmlExternalId)
  + XmlEndDoctype
  + XmlInstruction
  + XmlComment

removeUnusedXmlEvents
  :: Handler e (a * (b + c + d + XmlUnused))
  =>           [a * (b + c + d + XmlUnused)]
  -> [e] +     [a * (b + c + d            )]
removeUnusedXmlEvents = handleMap lens2e tryDrop4e

removeBeginElementNamespace
  :: Handler e (a * (XmlBeginElement * (XmlLocalName * (None + XmlNamespace) * (None + XmlNamePrefix)) * y + b2))
  =>           [a * (XmlBeginElement * (XmlLocalName * (None + XmlNamespace) * (None + XmlNamePrefix)) * y + b2)]
  -> [e] +     [a * (XmlBeginElement *  XmlLocalName                                                   * y + b2)]
removeBeginElementNamespace = handleMap (lens2e . prism1 . lens2) removeNamespace

removeEndElementNamespace
  :: Handler e (a * (b1 + XmlEndElement * XmlLocalName * (None + XmlNamespace) * (None + XmlNamePrefix) + b2))
  =>           [a * (b1 + XmlEndElement * XmlLocalName * (None + XmlNamespace) * (None + XmlNamePrefix) + b2)]
  -> [e] +     [a * (b1 + XmlEndElement * XmlLocalName                                                  + b2)]
removeEndElementNamespace = handleMap (lens2e . prism2 . lens2e) removeNamespace

useBeginElementType
  :: Handler e (a * (XmlBeginElement * XmlLocalName * as + b2))
  =>           [a * (XmlBeginElement * XmlLocalName * as + b2)]
  -> [e] +     [a * (XmlBeginElement * ElementAll   * as + b2)]
useBeginElementType = handleMap' (lens2e . prism1 . lens2) toElementAll

useEndElementType
  :: Handler e (a * (b1 + XmlEndElement * XmlLocalName + b3))
  =>           [a * (b1 + XmlEndElement * XmlLocalName + b3)]
  -> [e] +     [a * (b1 + XmlEndElement * ElementAll   + b3)]
useEndElementType = handleMap' (lens2e . prism2 . lens2e) toElementAll


newtype Sblgnt = Sblgnt () deriving (Eq, Ord, Show)

extractSblgnt
  :: Handler e (SublistErrorCase [a * FinalXmlEvent])
  => [a * FinalXmlEvent]
  -> [e] + [a * FinalXmlEvent + Sblgnt * [a * FinalXmlEvent]]
extractSblgnt = handleSublist buildSblgntSublist

topLevelSblgnt
  :: Handler e (a * FinalXmlEvent + Sblgnt * [a * FinalXmlEvent])
  => [a * FinalXmlEvent + Sblgnt * [a * FinalXmlEvent]]
  -> [e] + [Sblgnt * [a * FinalXmlEvent]]
topLevelSblgnt = handleMap (lens id (flip const)) tryDrop1


handleSublist
  :: Handler e (SublistErrorCase [a])
  => (a -> Sublist a t -> Sublist a t)
  -> [a]
  -> [e] + [a + t * [a]]
handleSublist f as = case foldr f (SublistOutside []) as of
  SublistError e -> sum1 $ handle e
  SublistInside (a, (as', _)) -> sum1 $ handle (OnlyBeginElement (a : as'))
  SublistOutside os -> sum2e os

data SublistErrorCase a
  = NestedSublist a
  | OnlyEndElement a
  | OnlyBeginElement a
  deriving (Show)

data Sublist a t
  = SublistError (SublistErrorCase [a])
  | SublistInside (a * [a] * [a + t * [a]])
  | SublistOutside [a + t * [a]]

buildSblgntSublist
  :: a * FinalXmlEvent
  -> Sublist (a * FinalXmlEvent) Sblgnt
  -> Sublist (a * FinalXmlEvent) Sblgnt
buildSblgntSublist x@(_, event) s
  | Left (XmlBeginElement _, (Left (SblgntElement _), [])) <- event
  = case s of
    e@(SublistError _) -> e
    SublistOutside os -> SublistInside (x * [] * os)
    SublistInside (a, (as, _)) -> SublistError $ NestedSublist (x : a : as)

  | Right (Left (XmlEndElement _, Left (SblgntElement _))) <- event
  = case s of
    e@(SublistError _) -> e
    SublistOutside _ -> SublistError $ OnlyEndElement [x]
    SublistInside (_, (as, os)) -> SublistOutside (sum2e (Sblgnt (), as) : os)

  | otherwise
  = case s of
    e@(SublistError _) -> e
    SublistInside i -> SublistInside (over lens2 (x :) i)
    SublistOutside os -> SublistOutside (sum1 x : os)

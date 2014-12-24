-- Copyright (C) 2013, 2014  Fraser Tweedale
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

{-|

Types to deal with the legacy JSON Web Key formats used with
Mozilla Persona.

-}
module Crypto.JOSE.Legacy
  (
    JWK'(..)
  , toJWK
  , RSKeyParameters()
  , rsaKeyParameters
  ) where

import Control.Applicative
import Data.Bifunctor

import Control.Lens hiding ((.=))
import Data.Aeson
import Data.Aeson.Types
import qualified Data.Text as T
import Safe (readMay)

import Crypto.JOSE.Classes
import Crypto.JOSE.JWA.JWK
import Crypto.JOSE.JWK
import qualified Crypto.JOSE.Types.Internal as Types
import Crypto.JOSE.Types
import Crypto.JOSE.TH


newtype StringifiedInteger = StringifiedInteger { _unString :: Integer }
makeLenses ''StringifiedInteger

instance FromJSON StringifiedInteger where
  parseJSON = withText "StringifiedInteger" $
    maybe (fail "not an stringy integer") (pure . StringifiedInteger)
    . readMay
    . T.unpack

instance ToJSON StringifiedInteger where
  toJSON (StringifiedInteger n) = toJSON $ show n

b64Iso :: Iso' StringifiedInteger Base64Integer
b64Iso = iso
  (Base64Integer . view unString)
  (\(Base64Integer n) -> StringifiedInteger n)

sizedB64Iso :: Iso' StringifiedInteger SizedBase64Integer
sizedB64Iso = iso
  (SizedBase64Integer 0 . view unString)
  (\(SizedBase64Integer _ n) -> StringifiedInteger n)


$(Crypto.JOSE.TH.deriveJOSEType "RS" ["RS"])


newtype RSKeyParameters = RSKeyParameters { _rsaKeyParameters :: RSAKeyParameters }
  deriving (Eq, Show)
makeLenses ''RSKeyParameters

instance FromJSON RSKeyParameters where
  parseJSON = withObject "RS" $ \o -> fmap RSKeyParameters $ RSAKeyParameters
    <$> ((o .: "algorithm" :: Parser RS) *> pure RSA)
    <*> (view sizedB64Iso <$> o .: "n")
    <*> (view b64Iso <$> o .: "e")
    <*> (fmap ((`RSAPrivateKeyParameters` Nothing) . view b64Iso) <$> (o .:? "d"))

instance ToJSON RSKeyParameters where
  toJSON (RSKeyParameters k)
    = object $
      [ "algorithm" .= RS
      , "n" .= (k ^. rsaN . from sizedB64Iso)
      , "e" .= (k ^. rsaE . from b64Iso)
      ]
      ++ maybe [] (\p -> ["d" .= (rsaD p ^. from b64Iso)])
        (k ^. rsaPrivateKeyParameters)

instance Key RSKeyParameters where
  type KeyGenParam RSKeyParameters = Int
  type KeyContent RSKeyParameters = RSAKeyParameters
  gen p = first fromKeyContent . gen p
  fromKeyContent = RSKeyParameters
  public = rsaKeyParameters public
  sign h (RSKeyParameters k) = sign h k
  verify h (RSKeyParameters k) = verify h k


-- | Legacy JSON Web Key data type.
--
newtype JWK' = JWK' { _rsKeyParameters :: RSKeyParameters }
  deriving (Eq, Show)
makeLenses ''JWK'

instance FromJSON JWK' where
  parseJSON = withObject "JWK'" $ \o -> JWK' <$> parseJSON (Object o)

instance ToJSON JWK' where
  toJSON (JWK' k) = object $ Types.objectPairs (toJSON k)

instance Key JWK' where
  type KeyGenParam JWK' = Int
  type KeyContent JWK' = RSKeyParameters
  gen p g = first JWK' $ gen p g
  fromKeyContent = JWK'
  public = rsKeyParameters public
  sign h (JWK' k) = sign h k
  verify h (JWK' k) = verify h k

toJWK :: JWK' -> JWK
toJWK (JWK' (RSKeyParameters k)) = fromKeyContent $ RSAKeyMaterial k

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

-- | Module of http://8tracks.com
module Radio.EightTracks where

import           Codec.Binary.UTF8.String (encodeString)
import           Control.Applicative ((<$>), (<*>))
import qualified Control.Exception as E
import           Control.Monad (liftM, mzero)
import           Data.Aeson
import           Data.Aeson.Types (defaultOptions, Options(..))
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as C
import qualified Data.HashMap.Strict as HM
import           Data.Maybe (fromJust, fromMaybe)
import qualified Data.Text as T
import           Data.Yaml hiding (decode)
import           Data.CaseInsensitive (mk)
import           Data.Conduit (($$+-))
import           Data.Conduit.Attoparsec (sinkParser)
import           GHC.Generics (Generic)
import           Network.HTTP.Types 
import           Network.HTTP.Conduit
import           System.IO
import           System.Directory (doesFileExist)

import qualified Radio


apiKey :: String
apiKey = "1de30eb2b8fe85b1740cfbee3fdbb928e2c7249b"

type Param a = Radio.Param EightTracks

data PlaySession = PlaySession
    { play_token            :: String
    , status                :: String
    , errors                :: Maybe String
    , notices               :: Maybe String
    , api_version           :: Int
    } deriving (Show, Generic)

data EightTracks = EightTracks 
    { track_file_stream_url :: String
    , name                  :: String
    , performer             :: String
    , release_name          :: String
    , url                   :: String
    } deriving (Show, Generic)

data MixSet = MixSet
    { at_beginning          :: Bool
    , at_last_track         :: Bool
    , at_end                :: Bool
    , skip_allowed          :: Bool
    , track                 :: EightTracks
    } deriving (Show, Generic)

data MixResponse = MixResponse
    { mix_set               :: MixSet
    , mix_status            :: String
    } deriving (Show, Generic)

instance FromJSON PlaySession
instance FromJSON EightTracks
instance FromJSON MixSet

instance FromJSON MixResponse where
    parseJSON = genericParseJSON defaultOptions { fieldLabelModifier = drop 4 }

instance Radio.Radio EightTracks where
    data Param EightTracks = Token
        { playToken     :: String
        , mixId         :: Int
        } deriving (Show, Generic)

    parsePlaylist val = do
        case fromJSON val of
            Success s -> [track $ mix_set s]
            Error err -> error $ "Parse playlist failed: " ++ show err

    getPlaylist tok = do
        let rurl = "http://8tracks.com/sets/" ++ playToken tok  ++ "/next.json"
            query = [ ("mix_id", C.pack $ show $ mixId tok) ]
            aHdr = (mk "X-Api-Version", "3") :: Header
            rHdr = (mk "X-Api-Key", C.pack apiKey) :: Header

        initReq <- parseUrl rurl
        let req = initReq { requestHeaders = [aHdr, rHdr] 
                          , queryString = renderSimpleQuery False query }
        withManager $ \manager -> do
            res <- http req manager
            liftM Radio.parsePlaylist (responseBody res $$+- sinkParser json)

    songUrl _ x = return $ track_file_stream_url x

    songMeta x = Radio.SongMeta (performer x) (release_name x) (name x)

    tagged _ = False
    
    playable _ = False

instance FromJSON (Radio.Param EightTracks)
instance ToJSON (Radio.Param EightTracks)

newSession :: Int -> IO (Radio.Param EightTracks)
newSession mId = do
    res <- simpleHttp rurl
    let ses = fromJust $ (decode res :: Maybe PlaySession)
    return $ Token (play_token ses) mId
  where
    rurl = "http://8tracks.com/sets/new.json?api_version=3&api_key=" ++ apiKey 

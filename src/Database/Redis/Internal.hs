{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Database.Redis.Internal (
    HostName,PortID(..),
    RedisConn(), connect, disconnect,
    Redis(),runRedis,
    send,
    recv,
    sendRequest
) where

import Control.Applicative
import Control.Monad.Reader
import Control.Concurrent
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Network (HostName, PortID(..), connectTo)
import System.IO (Handle, hFlush, hClose)

import Database.Redis.Reply
import Database.Redis.Request


------------------------------------------------------------------------------
-- Connection
--

-- |Connection to a Redis server. Use the 'connect' function to create one.
data RedisConn = Conn { connHandle :: Handle, connReplies :: MVar [Reply] }

-- |Opens a connection to a Redis server at the given host and port.
connect :: HostName -> PortID -> IO RedisConn
connect host port = do
    h       <- connectTo host port
    replies <- parseReply <$> LB.hGetContents h
    Conn h <$> newMVar replies

-- |Close the given connection.
disconnect :: RedisConn -> IO ()
disconnect (Conn h _) = hClose h


------------------------------------------------------------------------------
-- The Redis Monad
--
newtype Redis a = Redis (ReaderT RedisConn IO a)
    deriving (Monad, MonadIO, Functor)

runRedis :: RedisConn -> Redis a -> IO a
runRedis conn (Redis r) = runReaderT r conn

send :: [B.ByteString] -> Redis ()
send req = Redis $ do
    h <- asks connHandle
    liftIO $ do
        B.hPut h $ renderRequest req
        hFlush h

recv :: Redis Reply
recv = Redis $ do
    replies <- asks connReplies
    liftIO $ modifyMVar replies $ \(r:rs) -> return (rs,r)

-- |Send a request to the Redis server.
sendRequest :: [B.ByteString] -> Redis Reply
sendRequest req = send req >> recv

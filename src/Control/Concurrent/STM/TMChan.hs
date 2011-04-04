{-# OPTIONS_GHC -Wall -fwarn-tabs #-}
{-# LANGUAGE CPP, DeriveDataTypeable #-}
----------------------------------------------------------------
--                                                    2011.04.03
-- |
-- Module      :  Control.Concurrent.STM.TMChan
-- Copyright   :  Copyright (c) 2011 wren ng thornton
-- License     :  BSD
-- Maintainer  :  wren@community.haskell.org
-- Stability   :  experimental
-- Portability :  non-portable (GHC STM, DeriveDataTypeable)
--
-- A version of "Control.Concurrent.STM.TChan" where the queue is
-- closeable. This is similar to a @TChan (Maybe a)@ with a
-- monotonicity guarantee that once there's a @Nothing@ there will
-- always be @Nothing@.
----------------------------------------------------------------
module Control.Concurrent.STM.TMChan
    (
    -- * The TMChan type
      TMChan()
    -- ** Creating TMChans
    , newTMChan
    , newTMChanIO
    , dupTMChan
    -- ** Reading from TMChans
    , readTMChan
    , tryReadTMChan
    , peekTMChan
    , tryPeekTMChan
    -- ** Writing to TMChans
    , writeTMChan
    , unGetTMChan
    -- ** Closing TMChans
    , closeTMChan
    -- ** Predicates
    , isClosedTMChan
    , isEmptyTMChan
    ) where

import Data.Typeable       (Typeable)
import Control.Applicative ((<$>))
import Control.Monad.STM   (STM)
import Control.Concurrent.STM.TVar.Compat
import Control.Concurrent.STM.TChan.Compat -- N.B., GHC only

-- N.B., we need a Custom cabal build-type for this to work.
#ifdef __HADDOCK__
import Control.Monad.STM   (atomically)
import System.IO.Unsafe    (unsafePerformIO)
#endif
----------------------------------------------------------------

-- | @TMChan@ is an abstract type representing a closeable FIFO
-- channel.
data TMChan a = TMChan !(TVar Bool) !(TChan a)
    deriving Typeable


-- | Build and returns a new instance of @TMChan@.
newTMChan :: STM (TMChan a)
newTMChan = do
    closed <- newTVar False
    chan   <- newTChan
    return (TMChan closed chan)


-- | @IO@ version of 'newTMChan'. This is useful for creating
-- top-level @TMChan@s using 'unsafePerformIO', because using
-- 'atomically' inside 'unsafePerformIO' isn't possible.
newTMChanIO :: IO (TMChan a)
newTMChanIO = do
    closed <- newTVarIO False
    chan   <- newTChanIO
    return (TMChan closed chan)


-- | Duplicate a @TMChan@: the duplicate channel begins empty, but
-- data written to either channel from then on will be available
-- from both, and closing one copy will close them all. Hence this
-- creates a kind of broadcast channel, where data written by anyone
-- is seen by everyone else.
dupTMChan :: TMChan a -> STM (TMChan a)
dupTMChan (TMChan closed chan) = do
    new_chan <- dupTChan chan
    return (TMChan closed new_chan)


-- | Read the next value from the @TMChan@, retrying if the channel
-- is empty (and not closed). We return @Nothing@ immediately if
-- the channel is closed and empty.
readTMChan :: TMChan a -> STM (Maybe a)
readTMChan (TMChan closed chan) = do
    b  <- isEmptyTChan chan
    b' <- readTVar closed
    if b && b'
        then return Nothing
        else Just <$> readTChan chan


-- | A version of 'readTMChan' which does not retry. Instead it
-- returns @Just Nothing@ if the channel is open but no value is
-- available; it still returns @Nothing@ if the channel is closed
-- and empty.
tryReadTMChan :: TMChan a -> STM (Maybe (Maybe a))
tryReadTMChan (TMChan closed chan) = do
    b  <- isEmptyTChan chan
    b' <- readTVar closed
    if b && b'
        then return Nothing
        else Just <$> tryReadTChan chan


-- | Get the next value from the @TMChan@ without removing it,
-- retrying if the channel is empty.
peekTMChan :: TMChan a -> STM (Maybe a)
peekTMChan (TMChan closed chan) = do
    b  <- isEmptyTChan chan
    b' <- readTVar closed
    if b && b' 
        then return Nothing
        else Just <$> peekTChan chan


-- | A version of 'peekTMChan' which does not retry. Instead it
-- returns @Just Nothing@ if the channel is open but no value is
-- available; it still returns @Nothing@ if the channel is closed
-- and empty.
tryPeekTMChan :: TMChan a -> STM (Maybe (Maybe a))
tryPeekTMChan (TMChan closed chan) = do
    b  <- isEmptyTChan chan
    b' <- readTVar closed
    if b && b' 
        then return Nothing
        else Just <$> tryPeekTChan chan


-- | Write a value to a @TMChan@, retrying if the channel is full.
-- If the channel is closed then the value is silently discarded.
-- Use 'isClosedTMChan' to determine if the channel is closed before
-- writing, as needed.
writeTMChan :: TMChan a -> a -> STM ()
writeTMChan (TMChan closed chan) x = do
    b <- readTVar closed
    if b
        then return () -- discard silently
        else writeTChan chan x


-- | Put a data item back onto a channel, where it will be the next
-- item read. If the channel is closed then the value is silently
-- discarded; you can use 'peekTMChan' to circumvent this in certain
-- circumstances.
unGetTMChan :: TMChan a -> a -> STM ()
unGetTMChan (TMChan closed chan) x = do
    b <- readTVar closed
    if b
        then return () -- discard silently
        else unGetTChan chan x


-- | Closes the @TMChan@, preventing any further writes.
closeTMChan :: TMChan a -> STM ()
closeTMChan (TMChan closed _chan) =
    writeTVar closed True


-- | Returns @True@ if the supplied @TMChan@ has been closed.
isClosedTMChan :: TMChan a -> STM Bool
isClosedTMChan (TMChan closed _chan) =
    readTVar closed


-- | Returns @True@ if the supplied @TMChan@ is empty.
isEmptyTMChan :: TMChan a -> STM Bool
isEmptyTMChan (TMChan _closed chan) =
    isEmptyTChan chan

----------------------------------------------------------------
----------------------------------------------------------- fin.
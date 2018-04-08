{-
  Movie Monad
  (C) 2017 David Lettier
  lettier.com
-}

{-# LANGUAGE OverloadedStrings #-}

module PlayPause where

import Control.Monad
import Data.Text
import qualified GI.Gdk
import qualified GI.Gtk
import qualified GI.Gst

import qualified Records as R

addPlayPauseButtonClickHandler :: R.Application -> IO ()
addPlayPauseButtonClickHandler
  application@R.Application
    { R.guiObjects =
        R.GuiObjects
          { R.playPauseButton = playPauseButton
          }
    }
  =
  void $
    GI.Gtk.onWidgetButtonReleaseEvent
      playPauseButton $
        playPauseButtonClickHandler application

playPauseButtonClickHandler ::
  R.Application ->
  GI.Gdk.EventButton ->
  IO Bool
playPauseButtonClickHandler
  R.Application
    { R.guiObjects =
        R.GuiObjects
          { R.playPauseButton = playPauseButton
          , R.playImage = playImage
          , R.pauseImage = pauseImage
          }
    , R.playbin = playbin
    }
  _
  = do
  isPlaying <- isPlayPauseButtonPlaying playPauseButton
  if isPlaying
    then do
      setPlayPauseButton playPauseButton playImage pauseImage False
      void $ GI.Gst.elementSetState playbin GI.Gst.StatePaused
    else do
      setPlayPauseButton playPauseButton playImage pauseImage True
      void $ GI.Gst.elementSetState playbin GI.Gst.StatePlaying
  return False

setPlayPauseButton
  ::  GI.Gtk.Button
  ->  GI.Gtk.Image
  ->  GI.Gtk.Image
  ->  Bool
  ->  IO ()
setPlayPauseButton playPauseButton _ pauseImage True = do
  GI.Gtk.buttonSetImage playPauseButton (Just pauseImage)
  GI.Gtk.widgetSetTooltipText playPauseButton (Just "Click to Pause")
setPlayPauseButton playPauseButton playImage _ False = do
  GI.Gtk.buttonSetImage playPauseButton (Just playImage)
  GI.Gtk.widgetSetTooltipText playPauseButton (Just "Click to Play")

isPlayPauseButtonPlaying :: GI.Gtk.Button -> IO Bool
isPlayPauseButtonPlaying playPauseButton =
  GI.Gtk.buttonGetImage playPauseButton >>= getImage >>= getName >>= getMatch
  where
    getImage :: Maybe GI.Gtk.Widget -> IO (Maybe GI.Gtk.Image)
    getImage Nothing       = return Nothing
    getImage (Just widget) = GI.Gtk.castTo GI.Gtk.Image widget
    getName :: Maybe GI.Gtk.Image -> IO (Maybe Text)
    getName Nothing        = return Nothing
    getName (Just image)   = Just . Data.Text.strip . Data.Text.toLower <$> GI.Gtk.widgetGetName image
    getMatch :: Maybe Text -> IO Bool
    getMatch Nothing       = return False
    getMatch (Just text)   = return ("pause-image" == text)

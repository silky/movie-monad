{-
  Movie Monad
  (C) 2017 David Lettier
  lettier.com
-}

{-# LANGUAGE OverloadedStrings #-}

module FileChooser where

import Control.Monad
import Data.Maybe
import Data.Int
import Data.Text
import Data.IORef
import qualified Network.URI
import qualified GI.Gdk
import qualified GI.Gtk
import qualified GI.Gst

import qualified Records as R
import Constants
import Reset
import Window
import ErrorMessage
import VideoInfo
import Playbin
import Uri
import Utils

addFileChooserHandlers :: R.Application -> IO ()
addFileChooserHandlers
  application@R.Application
    { R.guiObjects =
        R.GuiObjects
          { R.fileChooserButton = fileChooserButton
          , R.fileChooserDialog = fileChooserDialog
          , R.fileChooserWidget = fileChooserWidget
          , R.fileChooserEntry  = fileChooserEntry
          }
    }
  = do
  void $
    GI.Gtk.onWidgetButtonReleaseEvent
      fileChooserButton $
        fileChooserButtonClickHandler application
  void $
    GI.Gtk.onDialogResponse
      fileChooserDialog $
        fileChooserDialogResponseHandler application
  void $
    GI.Gtk.onFileChooserSelectionChanged
      fileChooserWidget $
        fileChooserSelectionChangedHandler application
  void $
    GI.Gtk.onEntryIconRelease
      fileChooserEntry $ \ _ _ ->
        GI.Gtk.entrySetText fileChooserEntry ""

fileChooserDialogResponseHandler :: R.Application -> Int32 -> IO ()
fileChooserDialogResponseHandler
  application@R.Application
    { R.guiObjects =
        guiObjects@R.GuiObjects
          { R.window                           = window
          , R.videoWidget                      = videoWidget
          , R.windowWidthSelectionComboBoxText = windowWidthSelectionComboBoxText
          , R.fileChooserEntry                 = fileChooserEntry
          , R.fileChooserButtonLabel           = fileChooserButtonLabel
          , R.volumeButton                     = volumeButton
          , R.errorMessageDialog               = errorMessageDialog
          , R.fileChooserDialog                = fileChooserDialog
          }
    , R.ioRefs =
        R.IORefs
          { R.isWindowFullScreenRef   = isWindowFullScreenRef
          , R.videoInfoRef            = videoInfoRef
          , R.previousFileNamePathRef = previousFileNamePathRef
          }
    , R.playbin = playbin
    }
  responseId
  = do
  GI.Gtk.widgetHide fileChooserDialog
  if enumToInt32 GI.Gtk.ResponseTypeOk == responseId
    then do
      filePathName  <- GI.Gtk.entryGetText fileChooserEntry
      maybeFileName <- setFileChooserButtonLabel fileChooserButtonLabel filePathName
      case maybeFileName of
        (Just _) -> do
          let filePathNameStr = Data.Text.unpack filePathName
          videoInfo           <- fromMaybe R.defaultVideoInfo <$> getVideoInfo videoInfoRef filePathNameStr
          desiredWindowWidth  <- getDesiredWindowWidth windowWidthSelectionComboBoxText window
          maybeWindowSize     <- calculateWindowSize guiObjects desiredWindowWidth videoInfo
          case maybeWindowSize of
            Just (width, height) -> do
              videoWidgetName <- GI.Gtk.widgetGetName videoWidget
              if videoWidgetName == invalidVideoWidgetName
                then do
                  resetApplication application
                  runErrorMessageDialog
                    errorMessageDialog
                    "Cannot play the video. Please install the bad plugins, version 1.8 or higher, for GStreamer version 1."
                else do
                  isWindowFullScreen <- readIORef isWindowFullScreenRef
                  setupWindowForPlayback
                    application
                    (R.isSeekable videoInfo)
                    isWindowFullScreen
                    width
                    height
                  saveVideoInfo videoInfoRef videoInfo
                  resetPlaybin playbin
                  setPlaybinUriAndVolume playbin filePathNameStr volumeButton
                  void $ GI.Gst.elementSetState playbin GI.Gst.StatePlaying
            _ -> do
              resetApplication application
              runErrorMessageDialog
                errorMessageDialog $
                  Data.Text.pack $
                  Prelude.concat ["\"", filePathNameStr, "\" is not a video."]
        _ -> resetApplication application
    else do
      filePathName <- readIORef previousFileNamePathRef
      fromMaybe R.defaultVideoInfo <$>
        getVideoInfo videoInfoRef (Data.Text.unpack filePathName) >>=
          saveVideoInfo videoInfoRef
      _ <- setFileChooserButtonLabel fileChooserButtonLabel filePathName
      GI.Gtk.entrySetText fileChooserEntry filePathName

fileChooserButtonClickHandler :: R.Application -> GI.Gdk.EventButton -> IO Bool
fileChooserButtonClickHandler
  R.Application
    { R.guiObjects =
        R.GuiObjects
          { R.fileChooserEntry = fileChooserEntry
          , R.fileChooserDialog = fileChooserDialog
          }
    , R.ioRefs =
        R.IORefs
          { R.previousFileNamePathRef = previousFileNamePathRef
          }
    }
  _
  = do
  text <- GI.Gtk.entryGetText fileChooserEntry
  atomicWriteIORef previousFileNamePathRef text
  _ <- GI.Gtk.dialogRun fileChooserDialog
  return True

fileChooserSelectionChangedHandler :: R.Application -> IO ()
fileChooserSelectionChangedHandler
  R.Application
    { R.guiObjects =
        R.GuiObjects
          { R.fileChooserWidget = fileChooserWidget
          , R.fileChooserEntry  = fileChooserEntry
          }
    , R.ioRefs =
        R.IORefs
          { R.videoInfoRef = videoInfoRef
          }
    }
  = do
  maybeUri <- GI.Gtk.fileChooserGetUri fileChooserWidget
  case maybeUri of
    Nothing -> return ()
    Just uri' -> do
      let uri = Network.URI.unEscapeString $ Data.Text.unpack uri'
      local <- isLocalFile uri
      video <- R.isVideo . fromMaybe R.defaultVideoInfo <$> getVideoInfo videoInfoRef uri
      GI.Gtk.entrySetText
        fileChooserEntry $
          if local && video
            then Data.Text.pack uri
            else ""

setFileChooserButtonLabel :: GI.Gtk.Label -> Data.Text.Text -> IO (Maybe Data.Text.Text)
setFileChooserButtonLabel fileChooserButtonLabel filePathName = do
  let fileName = fileNameFromFilePathName filePathName
  let fileNameEmpty = isTextEmpty fileName
  if fileNameEmpty
    then do
      GI.Gtk.labelSetText fileChooserButtonLabel "Open"
      return Nothing
    else do
      GI.Gtk.labelSetText fileChooserButtonLabel fileName
      return $ Just fileName

{-# LANGUAGE OverloadedStrings #-}

module Main where

  import Control.Exception
  import Control.Monad
  import Data.Time
  import System.Environment
  import System.Exit
  import System.IO
  import Options.Applicative
  import Data.Semigroup ((<>))
  import Kit
  import Kit.Ast
  import Kit.Compiler
  import Kit.Error
  import Kit.HashTable
  import Kit.Log
  import Kit.Str

  data Options = Options {
    opt_show_version :: Bool,
    opt_verbose :: Bool,
    opt_target :: String,
    opt_main_module :: String,
    opt_output_dir :: FilePath,
    opt_source_paths :: [FilePath],
    opt_defines :: [String]
  } deriving (Eq, Show)

  options :: Parser Options
  options = Options
    <$> switch (long "version" <> short 'v' <> help "show the version number and exit")
    <*> switch (long "verbose" <> help "show extra debugging output")
    <*> strOption (long "target" <> short 't' <> showDefault <> value "c" <> metavar "TARGET" <> help "compile target (c|web|eval)")
    <*> strOption (long "main" <> short 'm' <> showDefault <> value "main" <> metavar "MODULE" <> help "module path containing main() function")
    <*> strOption (long "output" <> short 'o' <> showDefault <> value "build" <> metavar "DIR" <> help "sets the output directory")
    <*> many sourceDirParser
    <*> many definesParser

  sourceDirParser :: Parser String
  sourceDirParser = strOption (long "src" <> short 's' <> metavar "DIR" <> help "add a source directory")

  definesParser :: Parser String
  definesParser = strOption (long "define" <> short 'D' <> metavar "KEY[=VAL]" <> help "add a define")

  helper' :: Parser (a -> a)
  helper' = abortOption ShowHelpText $ mconcat [long "help", short 'h', help "show this help text and exit", hidden]

  p = prefs (showHelpOnError)

  main :: IO ()
  main = do
    startTime <- getCurrentTime
    argv <- getArgs
    let args = if length argv == 0 then ["--help"] else argv

    opts <- handleParseResult $ execParserPure p (info (options <**> helper') (fullDesc
                <> progDesc "This is the Kit compiler. It is generally used via the 'kit' build tool."
                <> header ("kitc v" ++ version)
              )) args

    if opt_show_version opts
      then putStrLn $ "kitc v" ++ version
      else do
        modules <- h_new
        std <- lookupEnv "KIT_STD_PATH"
        let std_path = case std of
                         Just x -> x
                         Nothing -> "std"
        let context = compile_context {
            context_main_module = parseModulePath $ s_pack $ opt_main_module opts,
            context_output_dir = opt_output_dir opts,
            context_source_paths = opt_source_paths opts ++ [std_path],
            context_defines = map (\s -> (takeWhile (/= '=') s, drop 1 $ dropWhile (/= '=') s)) (opt_defines opts),
            context_modules = modules,
            context_verbose = opt_verbose opts
          }

        result <- tryCompile context
        endTime <- getCurrentTime
        status <- case result of
          Left (Errs []) -> do logError (err Unknown ("An unknown error has occurred. Please report this!\n\n" ++ show context)); return 1
          Left (Errs errs) -> do forM errs logError; return 1
          Right () -> return 0
        printLog $ "total compile time: " ++ (show $ diffUTCTime endTime startTime)
        if status == 0
          then return ()
          else do
            errorLog $ "compilation failed"
            exitWith $ ExitFailure status

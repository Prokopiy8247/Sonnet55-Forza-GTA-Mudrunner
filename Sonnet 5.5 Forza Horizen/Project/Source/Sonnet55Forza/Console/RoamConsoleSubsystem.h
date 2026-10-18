// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Containers/RingBuffer.h"
#include "Containers/Ticker.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "RoamConsoleSubsystem.generated.h"

class APlayerController;
class URoamConsoleSubsystem;

/**
 * The Roamline developer console (Docs/ARCHITECTURE.md section 3): command registry, tokenizer, history and output buffer.
 * It has NO dependency on the UI - the Slate widget (UI owner) only calls Execute() and reads the output ring buffer, so
 * every command is testable headless (Automation tests "Roam.Console.*") and from the UE console:
 *
 *      roam <command> [args...]        e.g.   roam help     roam time 18     roam weather rain 10
 *
 * HOW TO ADD COMMANDS (any module file, no shared file to edit):
 *
 *      ROAM_REGISTER_CONSOLE_COMMAND("time", "time <hour>", "Set the game hour (0-24).",
 *          [](const FRoamConsoleContext& Ctx) -> FString
 *          {
 *              float Hour = 0.0f;
 *              if (!Ctx.GetFloat(0, Hour)) { return Ctx.Fail(TEXT("usage: time <hour>")); }
 *              ... use Ctx.World / Ctx.GameInstance / Ctx.PlayerController, look subsystems up at call time ...
 *              return FString::Printf(TEXT("time set to %.2f"), Hour);
 *          });
 *
 * Static registrations are collected before the subsystem exists and copied into it on Initialize(). Handlers must look their
 * targets up from the context at call time (never cache a world or subsystem in the lambda).
 */

/** Kind of an output line, for colouring in the console widget. */
UENUM(BlueprintType)
enum class ERoamConsoleLineKind : uint8
{
	Input = 0,   // echo of what the user typed
	Output,      // normal command output
	Error,       // failed command / usage error
	Info         // system messages (welcome text ...)
};

/** One line of the console output buffer. */
struct FRoamConsoleLine
{
	FString Text;
	ERoamConsoleLineKind Kind = ERoamConsoleLineKind::Output;
	/** FPlatformTime::Seconds() when the line was added. */
	double Time = 0.0;
	/** Monotonic id (never reused) so a widget can detect new lines cheaply. */
	int32 Id = 0;
};

/** Everything a command handler needs. Created per executed command. */
struct SONNET55FORZA_API FRoamConsoleContext
{
	URoamConsoleSubsystem* Console = nullptr;
	UGameInstance* GameInstance = nullptr;
	/** Game world; null in tests or while no map is loaded. */
	UWorld* World = nullptr;
	/** First local player controller if there is one. */
	APlayerController* PlayerController = nullptr;
	/** The command line of this command (one ';' separated piece), as typed. */
	FString RawLine;
	/** Lower-cased resolved command name (aliases already resolved). */
	FString CommandName;
	/** Tokens after the command name (quotes removed). */
	TArray<FString> Args;

	/** Set by Fail(); the output is then printed as an error. */
	mutable bool bFailed = false;

	int32 NumArgs() const { return Args.Num(); }
	const FString& Arg(int32 Index) const;
	bool HasArg(int32 Index) const { return Args.IsValidIndex(Index); }
	/** Strict parsers: false if missing or not a number. */
	bool GetInt(int32 Index, int32& OutValue) const;
	bool GetFloat(int32 Index, float& OutValue) const;
	/** Accepts on/off, true/false, yes/no, 1/0. */
	bool GetBool(int32 Index, bool& OutValue) const;
	/** All arguments from Index joined by single spaces. */
	FString JoinFrom(int32 Index) const;
	/** Returns Message and marks the command as failed. */
	FString Fail(const FString& Message) const
	{
		bFailed = true;
		return Message;
	}
};

/** Command handler: returns the output text (may be multi-line, may be empty). Use Ctx.Fail() for errors. */
using FRoamConsoleFn = TFunction<FString(const FRoamConsoleContext& Ctx)>;

/** Metadata + handler of a registered command. */
struct SONNET55FORZA_API FRoamConsoleCommand
{
	FName Name;
	/** Usage line, e.g. "time <hour>". */
	FString Usage;
	/** One-line help (plain string: registered at static-init time, before localisation is available). */
	FString Help;
	/** Grouping in `help` ("general", "car", "world", "traffic", "debug" ...). */
	FString Category = TEXT("general");
	FRoamConsoleFn Fn;
	TArray<FName> Aliases;
};

/** Static (pre-subsystem) registry used by ROAM_REGISTER_CONSOLE_COMMAND. */
class SONNET55FORZA_API FRoamConsoleRegistry
{
public:
	static TArray<FRoamConsoleCommand>& GetCommands();
	/** Broadcast when a command is registered after subsystems already exist (late module load). */
	static TMulticastDelegate<void(const FRoamConsoleCommand&)>& OnCommandAdded();
};

/** Static-initialiser object behind ROAM_REGISTER_CONSOLE_COMMAND. */
struct SONNET55FORZA_API FRoamConsoleAutoRegistrar
{
	FRoamConsoleAutoRegistrar(const TCHAR* Name, const TCHAR* Usage, const TCHAR* Help, FRoamConsoleFn Fn, const TCHAR* Category = TEXT("general"));
};

/**
 * Registers a command at static-initialisation time. Name/Usage/Help/Category are string literals; the last argument is the
 * handler (variadic so that commas inside a lambda body cannot break the macro).
 */
#define ROAM_REGISTER_CONSOLE_COMMAND(Name, Usage, Help, ...) \
	static FRoamConsoleAutoRegistrar UE_JOIN(GRoamConsoleCommand_, __LINE__)(TEXT(Name), TEXT(Usage), TEXT(Help), __VA_ARGS__)

/** Same with an explicit help category ("car", "world", "traffic", "debug", ...). */
#define ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY(Name, Usage, Help, Category, ...) \
	static FRoamConsoleAutoRegistrar UE_JOIN(GRoamConsoleCommand_, __LINE__)(TEXT(Name), TEXT(Usage), TEXT(Help), __VA_ARGS__, TEXT(Category))

DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnConsoleLine, const FRoamConsoleLine& /*NewLine*/);

UCLASS()
class SONNET55FORZA_API URoamConsoleSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	/** Convenience accessor from any object with a world. */
	static URoamConsoleSubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	//~ End USubsystem

	/** Registers built-in commands and the static registry without a game instance (automation tests). */
	void InitializeStandalone();

	// ---- registry --------------------------------------------------------------------------------------------------
	/** Registers (or replaces) a command. */
	void RegisterCommand(FName Name, const FText& Help, FRoamConsoleFn Fn, const FString& Usage = FString(), const FString& Category = TEXT("general"));
	void RegisterCommand(FName Name, const FString& Help, FRoamConsoleFn Fn, const FString& Usage = FString(), const FString& Category = TEXT("general"));
	void RegisterAlias(FName Alias, FName Name);
	bool UnregisterCommand(FName Name);
	bool HasCommand(FName Name) const;
	const FRoamConsoleCommand* FindCommand(FName NameOrAlias) const;
	/** All command names, sorted. */
	TArray<FName> GetCommandNames() const;
	/** Names starting with Prefix (case-insensitive), sorted - for tab completion. */
	TArray<FString> GetCompletions(const FString& Prefix) const;

	// ---- execution -------------------------------------------------------------------------------------------------
	/**
	 * Executes a line (one or more commands separated by ';' outside quotes). The input is added to the history and echoed
	 * to the output buffer, the output is appended to the buffer and also returned. Never throws, unknown commands print an error.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Console")
	FString Execute(const FString& Line);

	/** Unknown commands are offered to the engine console (stat fps, r.* ...). Default true. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Roam|Console")
	bool bFallbackToEngineConsole = true;

	/** Mirror console lines to the UE log (LogRoamConsole). Disabled in tests that must not spam. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Roam|Console")
	bool bMirrorToLog = true;

	/**
	 * Runs a command line after Seconds of REAL time (also while the game is paused). Used by automated runs, e.g.
	 *   -ExecCmds="roam delay 6 ue HighResShot 1280x720, roam delay 9 ue Quit"
	 * because -ExecCmds executes everything in the first frame and has no "wait". Returns an id for CancelDelayed.
	 */
	int32 ExecuteDelayed(const FString& Line, float Seconds);
	void CancelAllDelayed();

	// ---- tokenizer (pure, static, unit tested) ---------------------------------------------------------------------
	/**
	 * Splits a command line into tokens. Whitespace separates tokens; "double" or 'single' quotes group a token with spaces
	 * (the quotes are removed); a backslash escapes the next character (\" inside quotes, \\ ...). An unterminated quote
	 * returns false with OutError set, tokens parsed so far are still returned.
	 */
	static bool Tokenize(const FString& Line, TArray<FString>& OutTokens, FString* OutError = nullptr);
	/** Splits at ';' characters that are outside quotes. Empty pieces are dropped. */
	static void SplitCommands(const FString& Line, TArray<FString>& OutCommands);
	/** Joins tokens back into a line, quoting tokens that contain spaces or quotes (used by the `roam` UE console wrapper). */
	static FString JoinTokens(const TArray<FString>& Tokens);

	// ---- history ---------------------------------------------------------------------------------------------------
	const TArray<FString>& GetHistory() const { return History; }
	void AddToHistory(const FString& Line);
	void ClearHistory() { History.Reset(); }
	int32 MaxHistory = 200;

	// ---- output ring buffer ----------------------------------------------------------------------------------------
	int32 GetNumOutputLines() const { return Output.Num(); }
	const FRoamConsoleLine& GetOutputLine(int32 Index) const { return Output[Index]; }
	/** Appends text (multi-line text becomes several lines). */
	void Print(const FString& Text, ERoamConsoleLineKind Kind = ERoamConsoleLineKind::Output);
	void ClearOutput();
	int32 MaxOutputLines = 500;
	/** Broadcast for every line appended (UI invalidation). */
	FRoamOnConsoleLine OnLineAdded;

private:
	void RegisterBuiltinCommands();
	void ImportStaticCommands();
	void AddStaticCommand(const FRoamConsoleCommand& Command);
	FString ExecuteSingle(const FString& CommandLine);
	FRoamConsoleContext MakeContext() const;

	TMap<FName, FRoamConsoleCommand> Commands;
	TMap<FName, FName> AliasToCommand;
	TArray<FString> History;
	TRingBuffer<FRoamConsoleLine> Output;
	int32 NextLineId = 1;
	FDelegateHandle LateRegistrationHandle;
	TArray<FTSTicker::FDelegateHandle> DelayedHandles;
	bool bInitialized = false;
};

// --- added by menus (B2) ---
// Unity-build fix. Under MSVC __LINE__ inside a multi-line macro invocation is the LAST line of the invocation, so two
// registrations in different files of one unity blob (e.g. RoamGameMode.cpp "car" and RoamUISubsystem.cpp "speed", both ending
// on line 378) define the same static and the module fails to compile. __COUNTER__ is unique per translation unit.
#undef ROAM_REGISTER_CONSOLE_COMMAND
#undef ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY
#define ROAM_REGISTER_CONSOLE_COMMAND(Name, Usage, Help, ...) \
	static FRoamConsoleAutoRegistrar UE_JOIN(GRoamConsoleCommand_, __COUNTER__)(TEXT(Name), TEXT(Usage), TEXT(Help), __VA_ARGS__)
#define ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY(Name, Usage, Help, Category, ...) \
	static FRoamConsoleAutoRegistrar UE_JOIN(GRoamConsoleCommand_, __COUNTER__)(TEXT(Name), TEXT(Usage), TEXT(Help), __VA_ARGS__, TEXT(Category))
// --- end added by menus (B2) ---

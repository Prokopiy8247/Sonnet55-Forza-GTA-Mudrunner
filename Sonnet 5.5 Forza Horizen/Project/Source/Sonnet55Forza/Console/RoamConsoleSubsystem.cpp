// Copyright Epic Games, Inc. All Rights Reserved.

#include "Console/RoamConsoleSubsystem.h"

#include "Core/RoamLog.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "HAL/IConsoleManager.h"
#include "Misc/EngineVersion.h"
#include "Misc/StringOutputDevice.h"

// ------------------------------------------------------------------------------------------------------------------
// FRoamConsoleContext
// ------------------------------------------------------------------------------------------------------------------

const FString& FRoamConsoleContext::Arg(int32 Index) const
{
	static const FString Empty;
	return Args.IsValidIndex(Index) ? Args[Index] : Empty;
}

bool FRoamConsoleContext::GetInt(int32 Index, int32& OutValue) const
{
	if (!Args.IsValidIndex(Index))
	{
		return false;
	}
	const FString& Text = Args[Index];
	if (!Text.IsNumeric() || Text.Contains(TEXT(".")))
	{
		return false;
	}
	OutValue = FCString::Atoi(*Text);
	return true;
}

bool FRoamConsoleContext::GetFloat(int32 Index, float& OutValue) const
{
	if (!Args.IsValidIndex(Index) || !Args[Index].IsNumeric())
	{
		return false;
	}
	OutValue = FCString::Atof(*Args[Index]);
	return true;
}

bool FRoamConsoleContext::GetBool(int32 Index, bool& OutValue) const
{
	if (!Args.IsValidIndex(Index))
	{
		return false;
	}
	const FString Text = Args[Index].ToLower();
	if (Text == TEXT("on") || Text == TEXT("true") || Text == TEXT("yes") || Text == TEXT("1"))
	{
		OutValue = true;
		return true;
	}
	if (Text == TEXT("off") || Text == TEXT("false") || Text == TEXT("no") || Text == TEXT("0"))
	{
		OutValue = false;
		return true;
	}
	return false;
}

FString FRoamConsoleContext::JoinFrom(int32 Index) const
{
	FString Result;
	for (int32 i = FMath::Max(Index, 0); i < Args.Num(); ++i)
	{
		if (!Result.IsEmpty())
		{
			Result += TEXT(" ");
		}
		Result += Args[i];
	}
	return Result;
}

// ------------------------------------------------------------------------------------------------------------------
// Static registry
// ------------------------------------------------------------------------------------------------------------------

TArray<FRoamConsoleCommand>& FRoamConsoleRegistry::GetCommands()
{
	static TArray<FRoamConsoleCommand> Commands;
	return Commands;
}

TMulticastDelegate<void(const FRoamConsoleCommand&)>& FRoamConsoleRegistry::OnCommandAdded()
{
	static TMulticastDelegate<void(const FRoamConsoleCommand&)> Delegate;
	return Delegate;
}

FRoamConsoleAutoRegistrar::FRoamConsoleAutoRegistrar(const TCHAR* Name, const TCHAR* Usage, const TCHAR* Help, FRoamConsoleFn Fn, const TCHAR* Category)
{
	FRoamConsoleCommand Command;
	Command.Name = FName(Name);
	Command.Usage = Usage;
	Command.Help = Help;
	Command.Category = Category;
	Command.Fn = MoveTemp(Fn);
	FRoamConsoleRegistry::GetCommands().Add(Command);
	FRoamConsoleRegistry::OnCommandAdded().Broadcast(Command);
}

// ------------------------------------------------------------------------------------------------------------------
// Tokenizer
// ------------------------------------------------------------------------------------------------------------------

namespace
{
	bool IsEscapable(TCHAR C)
	{
		return C == TEXT('"') || C == TEXT('\'') || C == TEXT('\\');
	}
}

bool URoamConsoleSubsystem::Tokenize(const FString& Line, TArray<FString>& OutTokens, FString* OutError)
{
	OutTokens.Reset();
	if (OutError)
	{
		OutError->Reset();
	}

	FString Current;
	bool bInToken = false;
	TCHAR Quote = 0;

	const int32 Length = Line.Len();
	for (int32 i = 0; i < Length; ++i)
	{
		const TCHAR C = Line[i];

		// Backslash escapes only quotes and backslashes, so Windows paths like C:\tmp\file keep working.
		if (C == TEXT('\\') && i + 1 < Length && IsEscapable(Line[i + 1]))
		{
			Current.AppendChar(Line[i + 1]);
			bInToken = true;
			++i;
			continue;
		}

		if (Quote != 0)
		{
			if (C == Quote)
			{
				Quote = 0;
			}
			else
			{
				Current.AppendChar(C);
			}
			continue;
		}

		// Single quotes open a quoted token only at the start of a token, so "don't" stays one word.
		if (C == TEXT('"') || (C == TEXT('\'') && !bInToken))
		{
			Quote = C;
			bInToken = true; // an empty quoted string "" is a (empty) token
			continue;
		}

		if (FChar::IsWhitespace(C))
		{
			if (bInToken)
			{
				OutTokens.Add(Current);
				Current.Reset();
				bInToken = false;
			}
			continue;
		}

		Current.AppendChar(C);
		bInToken = true;
	}

	const bool bOk = (Quote == 0);
	if (!bOk && OutError)
	{
		*OutError = FString::Printf(TEXT("unterminated %c quote"), Quote);
	}
	if (bInToken)
	{
		OutTokens.Add(Current);
	}
	return bOk;
}

void URoamConsoleSubsystem::SplitCommands(const FString& Line, TArray<FString>& OutCommands)
{
	OutCommands.Reset();
	FString Current;
	TCHAR Quote = 0;
	bool bInToken = false;
	const int32 Length = Line.Len();
	for (int32 i = 0; i < Length; ++i)
	{
		const TCHAR C = Line[i];
		if (C == TEXT('\\') && i + 1 < Length && IsEscapable(Line[i + 1]))
		{
			Current.AppendChar(C);
			Current.AppendChar(Line[i + 1]);
			bInToken = true;
			++i;
			continue;
		}
		if (Quote != 0)
		{
			if (C == Quote)
			{
				Quote = 0;
			}
			Current.AppendChar(C);
			continue;
		}
		if (C == TEXT('"') || (C == TEXT('\'') && !bInToken))
		{
			Quote = C;
			bInToken = true;
			Current.AppendChar(C);
			continue;
		}
		if (C == TEXT(';'))
		{
			Current.TrimStartAndEndInline();
			if (!Current.IsEmpty())
			{
				OutCommands.Add(Current);
			}
			Current.Reset();
			bInToken = false;
			continue;
		}
		bInToken = !FChar::IsWhitespace(C);
		Current.AppendChar(C);
	}
	Current.TrimStartAndEndInline();
	if (!Current.IsEmpty())
	{
		OutCommands.Add(Current);
	}
}

FString URoamConsoleSubsystem::JoinTokens(const TArray<FString>& Tokens)
{
	FString Line;
	for (const FString& Token : Tokens)
	{
		if (!Line.IsEmpty())
		{
			Line += TEXT(" ");
		}
		const bool bNeedsQuotes = Token.IsEmpty() || Token.Contains(TEXT(" ")) || Token.Contains(TEXT("\"")) || Token.Contains(TEXT(";"));
		if (bNeedsQuotes)
		{
			FString Escaped = Token.Replace(TEXT("\\"), TEXT("\\\\")).Replace(TEXT("\""), TEXT("\\\""));
			Line += TEXT("\"") + Escaped + TEXT("\"");
		}
		else
		{
			Line += Token;
		}
	}
	return Line;
}

// ------------------------------------------------------------------------------------------------------------------
// Subsystem lifecycle
// ------------------------------------------------------------------------------------------------------------------

URoamConsoleSubsystem* URoamConsoleSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	const UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
	return GameInstance ? GameInstance->GetSubsystem<URoamConsoleSubsystem>() : nullptr;
}

void URoamConsoleSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	InitializeStandalone();
}

void URoamConsoleSubsystem::InitializeStandalone()
{
	if (bInitialized)
	{
		return;
	}
	bInitialized = true;
	RegisterBuiltinCommands();
	ImportStaticCommands();
	LateRegistrationHandle = FRoamConsoleRegistry::OnCommandAdded().AddUObject(this, &URoamConsoleSubsystem::AddStaticCommand);
	Print(TEXT("Roamline console ready. Type 'help' for commands."), ERoamConsoleLineKind::Info);
}

int32 URoamConsoleSubsystem::ExecuteDelayed(const FString& Line, float Seconds)
{
	const FTSTicker::FDelegateHandle Handle = FTSTicker::GetCoreTicker().AddTicker(
		FTickerDelegate::CreateWeakLambda(this, [this, Line](float) -> bool
		{
			Execute(Line);
			return false; // one shot
		}),
		FMath::Max(Seconds, 0.0f));
	DelayedHandles.Add(Handle);
	return DelayedHandles.Num();
}

void URoamConsoleSubsystem::CancelAllDelayed()
{
	for (FTSTicker::FDelegateHandle& Handle : DelayedHandles)
	{
		FTSTicker::GetCoreTicker().RemoveTicker(Handle);
	}
	DelayedHandles.Reset();
}

void URoamConsoleSubsystem::Deinitialize()
{
	CancelAllDelayed();
	FRoamConsoleRegistry::OnCommandAdded().Remove(LateRegistrationHandle);
	LateRegistrationHandle.Reset();
	Commands.Reset();
	AliasToCommand.Reset();
	bInitialized = false;
	Super::Deinitialize();
}

void URoamConsoleSubsystem::ImportStaticCommands()
{
	for (const FRoamConsoleCommand& Command : FRoamConsoleRegistry::GetCommands())
	{
		AddStaticCommand(Command);
	}
}

void URoamConsoleSubsystem::AddStaticCommand(const FRoamConsoleCommand& Command)
{
	// Static registrations never override a runtime registration of the same name that already exists.
	if (!Commands.Contains(Command.Name))
	{
		Commands.Add(Command.Name, Command);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Registry
// ------------------------------------------------------------------------------------------------------------------

void URoamConsoleSubsystem::RegisterCommand(FName Name, const FText& Help, FRoamConsoleFn Fn, const FString& Usage, const FString& Category)
{
	RegisterCommand(Name, Help.ToString(), MoveTemp(Fn), Usage, Category);
}

void URoamConsoleSubsystem::RegisterCommand(FName Name, const FString& Help, FRoamConsoleFn Fn, const FString& Usage, const FString& Category)
{
	if (Name.IsNone() || !Fn)
	{
		return;
	}
	FRoamConsoleCommand Command;
	Command.Name = Name;
	Command.Usage = Usage.IsEmpty() ? Name.ToString() : Usage;
	Command.Help = Help;
	Command.Category = Category;
	Command.Fn = MoveTemp(Fn);
	Commands.Add(Name, MoveTemp(Command));
}

void URoamConsoleSubsystem::RegisterAlias(FName Alias, FName Name)
{
	if (!Alias.IsNone() && !Name.IsNone())
	{
		AliasToCommand.Add(Alias, Name);
	}
}

bool URoamConsoleSubsystem::UnregisterCommand(FName Name)
{
	return Commands.Remove(Name) > 0;
}

bool URoamConsoleSubsystem::HasCommand(FName Name) const
{
	return FindCommand(Name) != nullptr;
}

const FRoamConsoleCommand* URoamConsoleSubsystem::FindCommand(FName NameOrAlias) const
{
	if (const FRoamConsoleCommand* Found = Commands.Find(NameOrAlias))
	{
		return Found;
	}
	if (const FName* Real = AliasToCommand.Find(NameOrAlias))
	{
		return Commands.Find(*Real);
	}
	return nullptr;
}

TArray<FName> URoamConsoleSubsystem::GetCommandNames() const
{
	TArray<FName> Names;
	Commands.GetKeys(Names);
	Names.Sort([](const FName& A, const FName& B) { return A.LexicalLess(B); });
	return Names;
}

TArray<FString> URoamConsoleSubsystem::GetCompletions(const FString& Prefix) const
{
	TArray<FString> Result;
	const FString Lower = Prefix.TrimStartAndEnd().ToLower();
	for (const TPair<FName, FRoamConsoleCommand>& Pair : Commands)
	{
		const FString Name = Pair.Key.ToString();
		if (Name.ToLower().StartsWith(Lower))
		{
			Result.Add(Name);
		}
	}
	for (const TPair<FName, FName>& Pair : AliasToCommand)
	{
		const FString Name = Pair.Key.ToString();
		if (Name.ToLower().StartsWith(Lower))
		{
			Result.AddUnique(Name);
		}
	}
	Result.Sort();
	return Result;
}

// ------------------------------------------------------------------------------------------------------------------
// History / output
// ------------------------------------------------------------------------------------------------------------------

void URoamConsoleSubsystem::AddToHistory(const FString& Line)
{
	const FString Trimmed = Line.TrimStartAndEnd();
	if (Trimmed.IsEmpty() || (History.Num() > 0 && History.Last() == Trimmed))
	{
		return;
	}
	History.Add(Trimmed);
	while (History.Num() > MaxHistory)
	{
		History.RemoveAt(0);
	}
}

void URoamConsoleSubsystem::Print(const FString& Text, ERoamConsoleLineKind Kind)
{
	TArray<FString> Lines;
	Text.ParseIntoArrayLines(Lines, false);
	if (Lines.Num() == 0)
	{
		Lines.Add(FString());
	}
	for (const FString& Piece : Lines)
	{
		FRoamConsoleLine Line;
		Line.Text = Piece;
		Line.Kind = Kind;
		Line.Time = FPlatformTime::Seconds();
		Line.Id = NextLineId++;
		Output.Add(Line);
		while (Output.Num() > MaxOutputLines)
		{
			Output.PopFront();
		}
		if (bMirrorToLog)
		{
			UE_LOG(LogRoamConsole, Log, TEXT("%s%s"), Kind == ERoamConsoleLineKind::Input ? TEXT("> ") : (Kind == ERoamConsoleLineKind::Error ? TEXT("ERROR: ") : TEXT("")), *Piece);
		}
		OnLineAdded.Broadcast(Line);
	}
}

void URoamConsoleSubsystem::ClearOutput()
{
	Output.Empty();
}

// ------------------------------------------------------------------------------------------------------------------
// Execution
// ------------------------------------------------------------------------------------------------------------------

FRoamConsoleContext URoamConsoleSubsystem::MakeContext() const
{
	FRoamConsoleContext Ctx;
	Ctx.Console = const_cast<URoamConsoleSubsystem*>(this);
	Ctx.GameInstance = GetGameInstance();
	Ctx.World = Ctx.GameInstance ? Ctx.GameInstance->GetWorld() : nullptr;
	Ctx.PlayerController = Ctx.World ? Ctx.World->GetFirstPlayerController() : nullptr;
	return Ctx;
}

FString URoamConsoleSubsystem::Execute(const FString& Line)
{
	const FString Trimmed = Line.TrimStartAndEnd();
	if (Trimmed.IsEmpty())
	{
		return FString();
	}
	AddToHistory(Trimmed);
	Print(Trimmed, ERoamConsoleLineKind::Input);

	TArray<FString> Pieces;
	SplitCommands(Trimmed, Pieces);

	FString Combined;
	for (const FString& Piece : Pieces)
	{
		const FString Result = ExecuteSingle(Piece);
		if (!Result.IsEmpty())
		{
			if (!Combined.IsEmpty())
			{
				Combined += TEXT("\n");
			}
			Combined += Result;
		}
	}
	return Combined;
}

FString URoamConsoleSubsystem::ExecuteSingle(const FString& CommandLine)
{
	TArray<FString> Tokens;
	FString ParseError;
	if (!Tokenize(CommandLine, Tokens, &ParseError))
	{
		const FString Message = FString::Printf(TEXT("parse error: %s"), *ParseError);
		Print(Message, ERoamConsoleLineKind::Error);
		return Message;
	}
	if (Tokens.Num() == 0)
	{
		return FString();
	}

	const FName CommandName(*Tokens[0]);
	const FRoamConsoleCommand* Command = FindCommand(CommandName);
	if (!Command)
	{
		// Offer it to the engine console (stat fps, r.ScreenPercentage 80, ...).
		if (bFallbackToEngineConsole && GEngine)
		{
			FStringOutputDevice Capture;
			UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr;
			APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
			bool bHandled = false;
			FString Text;
			if (PC)
			{
				Text = PC->ConsoleCommand(CommandLine, false).TrimStartAndEnd();
				bHandled = !Text.StartsWith(TEXT("Command not recognized"));
			}
			else
			{
				bHandled = GEngine->Exec(World, *CommandLine, Capture);
				Text = Capture.TrimStartAndEnd();
			}
			if (bHandled)
			{
				if (!Text.IsEmpty())
				{
					Print(Text, ERoamConsoleLineKind::Output);
				}
				return Text;
			}
		}
		FString Message = FString::Printf(TEXT("unknown command '%s'. Type 'help'."), *Tokens[0]);
		const TArray<FString> Suggestions = GetCompletions(Tokens[0].Left(2));
		if (Suggestions.Num() > 0)
		{
			Message += TEXT(" Did you mean: ") + FString::Join(Suggestions, TEXT(", ")) + TEXT("?");
		}
		Print(Message, ERoamConsoleLineKind::Error);
		return Message;
	}

	FRoamConsoleContext Ctx = MakeContext();
	Ctx.RawLine = CommandLine;
	Ctx.CommandName = Command->Name.ToString().ToLower();
	Ctx.Args = TArray<FString>(Tokens.GetData() + 1, Tokens.Num() - 1);

	// Copy the handler: it may (re)register commands and invalidate the map entry.
	const FRoamConsoleFn Handler = Command->Fn;
	const FString Result = Handler(Ctx);
	if (!Result.IsEmpty())
	{
		Print(Result, Ctx.bFailed ? ERoamConsoleLineKind::Error : ERoamConsoleLineKind::Output);
	}
	return Result;
}

// ------------------------------------------------------------------------------------------------------------------
// Built-in commands
// ------------------------------------------------------------------------------------------------------------------

void URoamConsoleSubsystem::RegisterBuiltinCommands()
{
	RegisterCommand(TEXT("help"), FString(TEXT("List all commands, or show usage and help of one command.")),
		[](const FRoamConsoleContext& Ctx) -> FString
		{
			const URoamConsoleSubsystem* Console = Ctx.Console;
			if (Ctx.NumArgs() >= 1)
			{
				const FRoamConsoleCommand* Command = Console->FindCommand(FName(*Ctx.Arg(0)));
				if (!Command)
				{
					return Ctx.Fail(FString::Printf(TEXT("no such command '%s'"), *Ctx.Arg(0)));
				}
				FString Text = FString::Printf(TEXT("%s\n  %s"), *Command->Usage, *Command->Help);
				if (Command->Aliases.Num() > 0)
				{
					Text += TEXT("\n  aliases: ");
					for (const FName& Alias : Command->Aliases)
					{
						Text += Alias.ToString() + TEXT(" ");
					}
				}
				return Text;
			}
			TMap<FString, TArray<const FRoamConsoleCommand*>> ByCategory;
			for (const FName& Name : Console->GetCommandNames())
			{
				if (const FRoamConsoleCommand* Command = Console->FindCommand(Name))
				{
					ByCategory.FindOrAdd(Command->Category).Add(Command);
				}
			}
			TArray<FString> Categories;
			ByCategory.GetKeys(Categories);
			Categories.Sort();
			FString Text = TEXT("Commands (type 'help <command>' for details; 'ue <cmd>' runs an engine console command):");
			for (const FString& Category : Categories)
			{
				Text += FString::Printf(TEXT("\n[%s]"), *Category);
				for (const FRoamConsoleCommand* Command : ByCategory[Category])
				{
					Text += FString::Printf(TEXT("\n  %-24s %s"), *Command->Usage, *Command->Help);
				}
			}
			return Text;
		},
		TEXT("help [command]"), TEXT("general"));

	RegisterCommand(TEXT("commands"), FString(TEXT("List the names of all commands on one line.")),
		[](const FRoamConsoleContext& Ctx) -> FString
		{
			FString Text;
			for (const FName& Name : Ctx.Console->GetCommandNames())
			{
				Text += Name.ToString() + TEXT(" ");
			}
			return Text.TrimEnd();
		},
		TEXT("commands"), TEXT("general"));

	RegisterCommand(TEXT("echo"), FString(TEXT("Print the arguments.")),
		[](const FRoamConsoleContext& Ctx) -> FString { return Ctx.JoinFrom(0); },
		TEXT("echo <text...>"), TEXT("general"));

	RegisterCommand(TEXT("clear"), FString(TEXT("Clear the console output.")),
		[](const FRoamConsoleContext& Ctx) -> FString
		{
			Ctx.Console->ClearOutput();
			return FString();
		},
		TEXT("clear"), TEXT("general"));
	RegisterAlias(TEXT("cls"), TEXT("clear"));

	RegisterCommand(TEXT("history"), FString(TEXT("Show the command history.")),
		[](const FRoamConsoleContext& Ctx) -> FString
		{
			FString Text;
			const TArray<FString>& History = Ctx.Console->GetHistory();
			for (int32 i = 0; i < History.Num(); ++i)
			{
				Text += FString::Printf(TEXT("%s%3d  %s"), i > 0 ? TEXT("\n") : TEXT(""), i + 1, *History[i]);
			}
			return Text;
		},
		TEXT("history"), TEXT("general"));

	RegisterCommand(TEXT("version"), FString(TEXT("Show the game and engine version.")),
		[](const FRoamConsoleContext&) -> FString
		{
			return FString::Printf(TEXT("Roamline: Open Roads - Unreal Engine %s"), *FEngineVersion::Current().ToString(EVersionComponent::Patch));
		},
		TEXT("version"), TEXT("general"));

	RegisterCommand(TEXT("delay"), FString(TEXT("Run a command after N seconds of real time (automation: delay 6 ue HighResShot 1280x720).")),
		[](const FRoamConsoleContext& Ctx) -> FString
		{
			float Seconds = 0.0f;
			if (Ctx.NumArgs() < 2 || !Ctx.GetFloat(0, Seconds))
			{
				return Ctx.Fail(TEXT("usage: delay <seconds> <command...>"));
			}
			Ctx.Console->ExecuteDelayed(URoamConsoleSubsystem::JoinTokens(TArray<FString>(Ctx.Args.GetData() + 1, Ctx.Args.Num() - 1)), Seconds);
			return FString::Printf(TEXT("scheduled in %.1f s: %s"), Seconds, *Ctx.JoinFrom(1));
		},
		TEXT("delay <seconds> <command...>"), TEXT("general"));

	RegisterCommand(TEXT("ue"), FString(TEXT("Run an Unreal Engine console command (stat fps, r.ScreenPercentage 80, ...).")),
		[](const FRoamConsoleContext& Ctx) -> FString
		{
			if (Ctx.NumArgs() == 0)
			{
				return Ctx.Fail(TEXT("usage: ue <engine console command>"));
			}
			if (!GEngine)
			{
				return Ctx.Fail(TEXT("no engine"));
			}
			const FString EngineCommand = Ctx.JoinFrom(0);
			// Through the player controller when there is one: that is the path of the typed console and the only one that reaches
			// viewport commands (HighResShot, Screenshot, ShowFlag ...). Without a player the engine handles what it can.
			if (Ctx.PlayerController)
			{
				const FString Text = Ctx.PlayerController->ConsoleCommand(EngineCommand, false).TrimStartAndEnd();
				if (Text.StartsWith(TEXT("Command not recognized")))
				{
					return Ctx.Fail(Text);
				}
				return Text;
			}
			FStringOutputDevice Capture;
			const bool bHandled = GEngine->Exec(Ctx.World, *EngineCommand, Capture);
			const FString Text = Capture.TrimStartAndEnd();
			if (!bHandled && Text.IsEmpty())
			{
				return Ctx.Fail(FString::Printf(TEXT("engine did not recognise '%s'"), *EngineCommand));
			}
			return Text;
		},
		TEXT("ue <engine command...>"), TEXT("general"));
}

// ------------------------------------------------------------------------------------------------------------------
// UE console wrapper:  roam <command ...>
// ------------------------------------------------------------------------------------------------------------------

namespace
{
	void ExecuteRoamFromEngineConsole(const TArray<FString>& Args, UWorld* World, FOutputDevice& Ar)
	{
		UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
		if (!GameInstance && GEngine)
		{
			for (const FWorldContext& Context : GEngine->GetWorldContexts())
			{
				if (Context.OwningGameInstance && (Context.WorldType == EWorldType::Game || Context.WorldType == EWorldType::PIE))
				{
					GameInstance = Context.OwningGameInstance;
					break;
				}
			}
		}
		URoamConsoleSubsystem* Console = GameInstance ? GameInstance->GetSubsystem<URoamConsoleSubsystem>() : nullptr;
		if (!Console)
		{
			Ar.Log(TEXT("roam: no Roamline game instance (is the game running with URoamGameInstance?)"));
			return;
		}
		const FString Line = Args.Num() > 0 ? URoamConsoleSubsystem::JoinTokens(Args) : FString(TEXT("help"));
		const FString Result = Console->Execute(Line);
		if (!Result.IsEmpty())
		{
			Ar.Log(*Result);
		}
	}

	FAutoConsoleCommandWithWorldArgsAndOutputDevice GRoamEngineConsoleCommand(
		TEXT("roam"),
		TEXT("Run a Roamline console command: roam <command> [args...]  (try: roam help)"),
		FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateStatic(&ExecuteRoamFromEngineConsole));
}

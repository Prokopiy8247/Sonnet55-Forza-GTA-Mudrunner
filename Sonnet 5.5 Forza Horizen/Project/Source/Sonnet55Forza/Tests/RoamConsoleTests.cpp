// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Console/RoamConsoleSubsystem.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "UObject/StrongObjectPtr.h"

// A command registered through the static macro, exercised by the test below ("test.add 2 3" -> "5").
ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("test.add", "test.add <a> <b>", "Adds two integers (automation test command).", "test",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		int32 A = 0;
		int32 B = 0;
		if (!Ctx.GetInt(0, A) || !Ctx.GetInt(1, B))
		{
			return Ctx.Fail(TEXT("usage: test.add <a> <b>"));
		}
		return FString::FromInt(A + B);
	});

#define ROAM_CONSOLE_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamConsoleTokenizerTest, "Roam.Console.Tokenizer", ROAM_CONSOLE_TEST_FLAGS)
bool FRoamConsoleTokenizerTest::RunTest(const FString& Parameters)
{
	const auto Tokenize = [](const FString& Line, bool* bOutOk = nullptr, FString* OutError = nullptr)
	{
		TArray<FString> Tokens;
		const bool bOk = URoamConsoleSubsystem::Tokenize(Line, Tokens, OutError);
		if (bOutOk)
		{
			*bOutOk = bOk;
		}
		return Tokens;
	};

	{
		const TArray<FString> T = Tokenize(TEXT("help"));
		TestEqual(TEXT("single token count"), T.Num(), 1);
		TestEqual(TEXT("single token"), T[0], FString(TEXT("help")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("   time    18  "));
		TestEqual(TEXT("whitespace collapses"), T.Num(), 2);
		TestEqual(TEXT("token 0"), T[0], FString(TEXT("time")));
		TestEqual(TEXT("token 1"), T[1], FString(TEXT("18")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("echo \"hello world\" foo"));
		TestEqual(TEXT("double quotes group"), T.Num(), 3);
		TestEqual(TEXT("quoted token has no quotes"), T[1], FString(TEXT("hello world")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("echo 'single quoted words' x"));
		TestEqual(TEXT("single quotes group at token start"), T.Num(), 3);
		TestEqual(TEXT("single quoted token"), T[1], FString(TEXT("single quoted words")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("echo don't stop"));
		TestEqual(TEXT("apostrophe inside a word is literal"), T.Num(), 3);
		TestEqual(TEXT("apostrophe word"), T[1], FString(TEXT("don't")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("say \"a \\\"quoted\\\" word\""));
		TestEqual(TEXT("escaped quotes"), T.Num(), 2);
		TestEqual(TEXT("escaped quote content"), T[1], FString(TEXT("a \"quoted\" word")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("path C:\\tmp\\file.txt"));
		TestEqual(TEXT("windows path token count"), T.Num(), 2);
		TestEqual(TEXT("backslashes before ordinary characters stay"), T[1], FString(TEXT("C:\\tmp\\file.txt")));
	}
	{
		const TArray<FString> T = Tokenize(TEXT("x \"\" y"));
		TestEqual(TEXT("empty quoted string is a token"), T.Num(), 3);
		TestEqual(TEXT("empty token"), T[1], FString());
	}
	{
		bool bOk = true;
		FString Error;
		const TArray<FString> T = Tokenize(TEXT("echo \"unterminated text"), &bOk, &Error);
		TestFalse(TEXT("unterminated quote reports failure"), bOk);
		TestTrue(TEXT("unterminated quote has an error message"), !Error.IsEmpty());
		TestEqual(TEXT("tokens parsed so far are kept"), T.Num(), 2);
		TestEqual(TEXT("partial token"), T[1], FString(TEXT("unterminated text")));
	}
	{
		TestEqual(TEXT("blank line has no tokens"), Tokenize(TEXT("   \t ")).Num(), 0);
		TestEqual(TEXT("empty line has no tokens"), Tokenize(FString()).Num(), 0);
	}
	{
		TArray<FString> Pieces;
		URoamConsoleSubsystem::SplitCommands(TEXT("a 1; b \"x;y\"; ;c"), Pieces);
		TestEqual(TEXT("split piece count"), Pieces.Num(), 3);
		if (Pieces.Num() == 3)
		{
			TestEqual(TEXT("piece 0"), Pieces[0], FString(TEXT("a 1")));
			TestEqual(TEXT("semicolon inside quotes does not split"), Pieces[1], FString(TEXT("b \"x;y\"")));
			TestEqual(TEXT("piece 2"), Pieces[2], FString(TEXT("c")));
		}
	}
	{
		// JoinTokens must round-trip through Tokenize (used by the `roam <cmd>` engine-console wrapper).
		const TArray<FString> Original = { TEXT("paint"), TEXT("dark red"), TEXT("say \"hi\""), TEXT(""), TEXT("a;b"), TEXT("plain") };
		const FString Joined = URoamConsoleSubsystem::JoinTokens(Original);
		const TArray<FString> RoundTrip = Tokenize(Joined);
		TestEqual(TEXT("round trip count"), RoundTrip.Num(), Original.Num());
		for (int32 i = 0; i < FMath::Min(RoundTrip.Num(), Original.Num()); ++i)
		{
			TestEqual(*FString::Printf(TEXT("round trip token %d"), i), RoundTrip[i], Original[i]);
		}
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamConsoleCommandsTest, "Roam.Console.Commands", ROAM_CONSOLE_TEST_FLAGS)
bool FRoamConsoleCommandsTest::RunTest(const FString& Parameters)
{
	// Game-instance subsystems must be created inside a UGameInstance (ClassWithin); the instance is never initialised.
	TStrongObjectPtr<UGameInstance> GameInstance(NewObject<UGameInstance>(GEngine));
	TStrongObjectPtr<URoamConsoleSubsystem> Console(NewObject<URoamConsoleSubsystem>(GameInstance.Get()));
	Console->bMirrorToLog = false;
	Console->bFallbackToEngineConsole = false;
	Console->InitializeStandalone();

	// built-ins
	TestTrue(TEXT("help exists"), Console->HasCommand(TEXT("help")));
	TestTrue(TEXT("echo exists"), Console->HasCommand(TEXT("echo")));
	TestTrue(TEXT("clear exists"), Console->HasCommand(TEXT("clear")));
	TestTrue(TEXT("commands exists"), Console->HasCommand(TEXT("commands")));
	TestTrue(TEXT("command lookup is case-insensitive"), Console->HasCommand(TEXT("HELP")));
	TestTrue(TEXT("alias cls resolves"), Console->HasCommand(TEXT("cls")));

	TestEqual(TEXT("echo"), Console->Execute(TEXT("echo hello   world")), FString(TEXT("hello world")));
	TestEqual(TEXT("echo keeps quoted spaces"), Console->Execute(TEXT("echo \"a  b\"")), FString(TEXT("a  b")));
	TestTrue(TEXT("help lists echo"), Console->Execute(TEXT("help")).Contains(TEXT("echo")));
	TestTrue(TEXT("help <cmd> shows usage"), Console->Execute(TEXT("help echo")).Contains(TEXT("echo <text...>")));
	TestTrue(TEXT("commands lists clear"), Console->Execute(TEXT("commands")).Contains(TEXT("clear")));

	// static macro registration reaches the subsystem
	TestTrue(TEXT("static command registered"), Console->HasCommand(TEXT("test.add")));
	TestEqual(TEXT("static command executes"), Console->Execute(TEXT("test.add 2 3")), FString(TEXT("5")));
	const int32 LinesBefore = Console->GetNumOutputLines();
	const FString UsageError = Console->Execute(TEXT("test.add 2"));
	TestTrue(TEXT("usage error text"), UsageError.Contains(TEXT("usage")));
	TestEqual(TEXT("error line is marked as error"), Console->GetOutputLine(Console->GetNumOutputLines() - 1).Kind, ERoamConsoleLineKind::Error);
	TestTrue(TEXT("output grew"), Console->GetNumOutputLines() > LinesBefore);

	// runtime registration and argument helpers
	Console->RegisterCommand(TEXT("mix"), FString(TEXT("test helper")), [](const FRoamConsoleContext& Ctx) -> FString
	{
		float F = 0.0f;
		bool B = false;
		int32 I = 0;
		if (!Ctx.GetFloat(0, F) || !Ctx.GetBool(1, B) || !Ctx.GetInt(2, I))
		{
			return Ctx.Fail(TEXT("bad args"));
		}
		return FString::Printf(TEXT("%.1f %d %d %s"), F, B ? 1 : 0, I, *Ctx.JoinFrom(3));
	}, TEXT("mix <float> <bool> <int> [rest...]"));
	TestEqual(TEXT("argument parsing"), Console->Execute(TEXT("mix 2.5 on 7 tail words")), FString(TEXT("2.5 1 7 tail words")));
	TestEqual(TEXT("bool words"), Console->Execute(TEXT("mix 1 off 3")), FString(TEXT("1.0 0 3 ")));
	TestTrue(TEXT("int rejects floats"), Console->Execute(TEXT("mix 1 on 2.5")).Contains(TEXT("bad args")));

	// several commands in one line
	TestEqual(TEXT("semicolon separated commands"), Console->Execute(TEXT("echo one; echo two")), FString(TEXT("one\ntwo")));

	// unknown command
	const FString Unknown = Console->Execute(TEXT("definitelynotacommand 1 2"));
	TestTrue(TEXT("unknown command reports"), Unknown.Contains(TEXT("unknown command")));

	// parse error does not crash and is reported
	TestTrue(TEXT("unterminated quote is reported"), Console->Execute(TEXT("echo \"oops")).Contains(TEXT("parse error")));

	// completions
	const TArray<FString> Completions = Console->GetCompletions(TEXT("he"));
	TestTrue(TEXT("completion offers help"), Completions.Contains(TEXT("help")));

	// history: duplicates collapse, order kept, clear works
	Console->ClearHistory();
	Console->Execute(TEXT("echo a"));
	Console->Execute(TEXT("echo a"));
	Console->Execute(TEXT("echo b"));
	TestEqual(TEXT("history without consecutive duplicates"), Console->GetHistory().Num(), 2);
	TestEqual(TEXT("history last"), Console->GetHistory().Last(), FString(TEXT("echo b")));

	// output ring buffer is bounded
	Console->MaxOutputLines = 20;
	for (int32 i = 0; i < 100; ++i)
	{
		Console->Print(FString::Printf(TEXT("line %d"), i));
	}
	TestEqual(TEXT("output ring buffer is capped"), Console->GetNumOutputLines(), 20);
	TestEqual(TEXT("newest line kept"), Console->GetOutputLine(19).Text, FString(TEXT("line 99")));
	Console->Execute(TEXT("clear"));
	TestEqual(TEXT("clear empties the output (the echo of 'clear' itself is also removed)"), Console->GetNumOutputLines(), 0);

	Console->Deinitialize();
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

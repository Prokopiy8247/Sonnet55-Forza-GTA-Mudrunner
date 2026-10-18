// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamNotifications.h"

#include "Data/RoamWorldDefinition.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"

using namespace RoamUI;

namespace
{
	FString FitText(const FString& Text, const FSlateFontInfo& FontInfo, float MaxWidth)
	{
		if (MeasureText(Text, FontInfo).X <= MaxWidth)
		{
			return Text;
		}
		FString Cut = Text;
		while (Cut.Len() > 1 && MeasureText(Cut + TEXT("..."), FontInfo).X > MaxWidth)
		{
			Cut.LeftChopInline(1, EAllowShrinking::No);
		}
		return Cut + TEXT("...");
	}

	const TCHAR* ActivityTypeLabel(ERoamActivityType Type)
	{
		switch (Type)
		{
		case ERoamActivityType::SpeedTrap: return TEXT("SPEED TRAP");
		case ERoamActivityType::SpeedZone: return TEXT("SPEED ZONE");
		case ERoamActivityType::DriftZone: return TEXT("DRIFT ZONE");
		case ERoamActivityType::DangerSign: return TEXT("DANGER SIGN");
		case ERoamActivityType::CheckpointRace: return TEXT("RACE");
		case ERoamActivityType::TimeTrial: return TEXT("TIME TRIAL");
		case ERoamActivityType::Collectible: return TEXT("COLLECTIBLE");
		case ERoamActivityType::PhotoSpot: return TEXT("PHOTO SPOT");
		default: return TEXT("EVENT");
		}
	}

	FString GroupedInt(int32 Value)
	{
		FString Digits = FString::FromInt(FMath::Abs(Value));
		for (int32 i = Digits.Len() - 3; i > 0; i -= 3)
		{
			Digits.InsertAt(i, TEXT(","));
		}
		return Value < 0 ? TEXT("-") + Digits : Digits;
	}

	void PaintStars(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& CenterOfFirst, float Radius, float Spacing, int32 Lit, int32 Total, float Alpha)
	{
		static thread_local TArray<FVector2f> Points;
		for (int32 i = 0; i < Total; ++i)
		{
			MakeStarPoints(CenterOfFirst + FVector2f(Spacing * static_cast<float>(i), 0.0f), Radius, Points);
			DrawPolygon(Out, Layer, G, Points, i < Lit ? Color::WithAlpha(Color::Amber(), Alpha) : FLinearColor(1.0f, 1.0f, 1.0f, 0.16f * Alpha));
		}
	}
}

void SRoamNotifications::Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI)
{
	UI = InUI;
	SetCanTick(true);
	SetVisibility(EVisibility::HitTestInvisible);
	if (URoamUISubsystem* Subsystem = UI.Get())
	{
		NotificationHandle = Subsystem->OnNotificationPushed.AddSP(this, &SRoamNotifications::HandleNotification);
		RegionHandle = Subsystem->OnRegionPopup.AddSP(this, &SRoamNotifications::HandleRegionPopup);
	}
}

SRoamNotifications::~SRoamNotifications()
{
	if (URoamUISubsystem* Subsystem = UI.Get())
	{
		Subsystem->OnNotificationPushed.Remove(NotificationHandle);
		Subsystem->OnRegionPopup.Remove(RegionHandle);
	}
}

void SRoamNotifications::SetEventOverride(const FRoamActivityLiveInfo* LiveInfo, const FText& Title)
{
	bEventOverride = LiveInfo != nullptr;
	if (LiveInfo)
	{
		EventOverrideInfo = *LiveInfo;
		EventOverrideTitle = Title;
		EventOverrideSetAt = FPlatformTime::Seconds();
	}
}

void SRoamNotifications::HandleNotification(const FRoamNotification& Notification)
{
	const double Time = FPlatformTime::Seconds();
	switch (Notification.Kind)
	{
	case ERoamNotifyKind::Banner: Banners.Push(Notification, Time); break;
	case ERoamNotifyKind::ResultCard: Cards.Push(Notification, Time); break;
	default: Toasts.Push(Notification, Time); break;
	}
}

void SRoamNotifications::HandleRegionPopup(const FText& Name, const FText& Subtitle)
{
	RegionName = Name.ToString().ToUpper();
	RegionSubtitle = Subtitle.ToString();
	RegionShownAt = FPlatformTime::Seconds();
}

void SRoamNotifications::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SLeafWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	Now = FPlatformTime::Seconds();
	Toasts.Update(Now);
	Banners.Update(Now);
	Cards.Update(Now);

	const URoamUISubsystem* Subsystem = UI.Get();
	bool bHudVisible = true;
	if (const URoamSaveSubsystem* Save = (Subsystem && Subsystem->GetGameInstance()) ? Subsystem->GetGameInstance()->GetSubsystem<URoamSaveSubsystem>() : nullptr)
	{
		bHudVisible = Save->GetSettings().bHudVisible;
		bShowNotifications = Save->GetSettings().bShowNotifications;
		bMph = Save->GetSettings().bUseMph;
	}
	SetVisibility(bHudVisible ? EVisibility::HitTestInvisible : EVisibility::Collapsed);

	// event bar data
	bEventActive = false;
	if (bEventOverride)
	{
		EventInfo = EventOverrideInfo;
		EventInfo.ElapsedSec += static_cast<float>(Now - EventOverrideSetAt);
		EventTitle = EventOverrideTitle.ToString().ToUpper();
		bEventActive = true;
	}
	else if (Subsystem && Subsystem->GetGameInstance() && Subsystem->GetGameInstance()->GetWorld())
	{
		if (const URoamActivitySubsystem* Activities = URoamActivitySubsystem::Get(Subsystem->GetGameInstance()->GetWorld()))
		{
			if (Activities->GetLiveInfo(EventInfo))
			{
				bEventActive = true;
				const FRoamActivityDef* Def = Activities->FindActivity(EventInfo.ActivityId);
				EventTitle = Def && !Def->DisplayName.IsEmpty() ? Def->DisplayName.ToString().ToUpper() : EventInfo.ActivityId.ToString().ToUpper();
			}
		}
	}
	if (bEventActive)
	{
		EventTypeText = ActivityTypeLabel(EventInfo.Type);
		EventTimerText = Logic::FormatTimer(EventInfo.ElapsedSec);
		switch (EventInfo.Type)
		{
		case ERoamActivityType::SpeedZone:
		case ERoamActivityType::SpeedTrap:
			EventValueText = FString::Printf(TEXT("%d %s"), Logic::SpeedValue(EventInfo.Value, bMph), Logic::UnitLabel(bMph));
			EventValueLabel = TEXT("AVERAGE");
			break;
		case ERoamActivityType::DriftZone:
			EventValueText = GroupedInt(FMath::RoundToInt(EventInfo.Value));
			EventValueLabel = EventInfo.Multiplier > 1 ? FString::Printf(TEXT("CHAIN +%d  x%d"), FMath::RoundToInt(EventInfo.ChainScore), EventInfo.Multiplier) : FString(TEXT("POINTS"));
			break;
		case ERoamActivityType::DangerSign:
			EventValueText = FString::Printf(TEXT("%.0f m"), EventInfo.Value);
			EventValueLabel = TEXT("DISTANCE");
			break;
		case ERoamActivityType::CheckpointRace:
		case ERoamActivityType::TimeTrial:
			EventValueText = EventInfo.NumCheckpoints > 0 ? FString::Printf(TEXT("%d / %d"), EventInfo.Checkpoint, EventInfo.NumCheckpoints) : EventTimerText;
			EventValueLabel = TEXT("CHECKPOINT");
			break;
		default:
			EventValueText = FString::Printf(TEXT("%.0f"), EventInfo.Value);
			EventValueLabel = TEXT("");
			break;
		}
	}
}

void SRoamNotifications::PaintToast(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const Logic::FNotificationChannel::FEntry& Entry, const FVector2f& Origin, float Alpha) const
{
	const FRoamNotification& N = Entry.Data;
	const FVector2f Size(Layout::ToastW, Layout::ToastH);
	DrawBox(Out, Layer, G, Origin, Size, Brushes::Panel(), Color::WithAlpha(Color::Glass(), Alpha));
	DrawBox(Out, Layer + 1, G, Origin + FVector2f(0.0f, 10.0f), FVector2f(5.0f, Size.Y - 20.0f), Brushes::Pill(), Color::WithAlpha(N.Color, Alpha));
	const FSlateFontInfo TitleFont = Font(22, true);
	const FSlateFontInfo BodyFont = Font(17);
	PaintText(Out, Layer + 2, G, Origin + FVector2f(24.0f, 9.0f), FitText(N.Title.ToString().ToUpper(), TitleFont, Size.X - 44.0f), TitleFont, Color::WithAlpha(Color::Chalk(), Alpha));
	PaintText(Out, Layer + 2, G, Origin + FVector2f(24.0f, 38.0f), FitText(N.Body.ToString(), BodyFont, Size.X - 44.0f), BodyFont, Color::WithAlpha(Color::Dim(), Alpha));
}

int32 SRoamNotifications::OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
	int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const
{
	const FGeometry& G = AllottedGeometry;
	const FVector2f View = G.GetLocalSize();
	const Logic::FSafeArea Safe = Logic::ComputeSafeArea(View);
	int32 Layer = LayerId;

	// ---- region popup (top-left)
	{
		const Logic::FPhase Phase = Logic::RegionPopupPhase(static_cast<float>(Now - RegionShownAt));
		if (Phase.bVisible && !RegionName.IsEmpty())
		{
			const FVector2f Origin(Safe.Left - (1.0f - Phase.Slide) * 90.0f, Safe.Top);
			const float A = Phase.Alpha;
			DrawBox(OutDrawElements, Layer, G, Origin, FVector2f(Layout::RegionPopupW, Layout::RegionPopupH), Brushes::Panel(), Color::WithAlpha(Color::Glass(), A));
			DrawBox(OutDrawElements, Layer + 1, G, Origin + FVector2f(0.0f, 12.0f), FVector2f(6.0f, Layout::RegionPopupH - 24.0f), Brushes::Pill(), Color::WithAlpha(Color::Orange(), A));
			const FSlateFontInfo TitleFont = Font(34, true);
			PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(30.0f, 8.0f), FitText(RegionName, TitleFont, Layout::RegionPopupW - 60.0f), TitleFont, Color::WithAlpha(Color::Chalk(), A), ETextAnchor::Left, true);
			if (!RegionSubtitle.IsEmpty())
			{
				const FSlateFontInfo SubFont = Font(19);
				PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(31.0f, 52.0f), FitText(RegionSubtitle, SubFont, Layout::RegionPopupW - 60.0f), SubFont, Color::WithAlpha(Color::Teal(), A));
			}
		}
		Layer += 4;
	}

	// ---- event bar (top-centre)
	if (bEventActive)
	{
		// Sits below the "press ~ for console" hint (top-centre, B2) so the two never overlap.
		const FVector2f Origin((View.X - Layout::EventBarW) * 0.5f, Safe.Top + 46.0f);
		const FVector2f Size(Layout::EventBarW, Layout::EventBarH);
		DrawBox(OutDrawElements, Layer, G, Origin, Size, Brushes::Panel(), Color::Glass());
		DrawBox(OutDrawElements, Layer + 1, G, Origin + FVector2f(0.0f, 12.0f), FVector2f(5.0f, Size.Y - 24.0f), Brushes::Pill(), Color::WithAlpha(Color::Orange(), 0.95f));
		const FSlateFontInfo TitleFont = Font(21, true);
		PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(22.0f, 12.0f), FitText(EventTitle, TitleFont, 246.0f), TitleFont, Color::Chalk());
		FString Sub = EventTypeText;
		if (EventInfo.NumCheckpoints > 0 && EventInfo.Type != ERoamActivityType::CheckpointRace && EventInfo.Type != ERoamActivityType::TimeTrial)
		{
			Sub += FString::Printf(TEXT("   %d/%d"), EventInfo.Checkpoint, EventInfo.NumCheckpoints);
		}
		PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(22.0f, 46.0f), Sub, Font(16, true), Color::Orange());

		PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(386.0f, 8.0f), EventValueText, Font(36, true), Color::Chalk(), ETextAnchor::Center, true);
		if (!EventValueLabel.IsEmpty())
		{
			PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(386.0f, 56.0f), EventValueLabel, Font(13, true), Color::Dim(), ETextAnchor::Center);
		}
		PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X - 20.0f, 10.0f), EventTimerText, Font(24, true), Color::Teal(), ETextAnchor::Right);
		PaintStars(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X - 20.0f - 2.0f * 26.0f - 10.0f, 56.0f), 10.0f, 26.0f, EventInfo.StarsNow, 3, 1.0f);
	}
	Layer += 4;

	if (bShowNotifications)
	{
		// ---- toast stack (top-right)
		{
			int32 Slot = 0;
			for (const Logic::FNotificationChannel::FEntry& Entry : Toasts.GetVisible())
			{
				const Logic::FPhase Phase = Logic::NotificationPhase(Logic::FNotificationChannel::AgeOf(Entry, Now), Entry.HoldSec);
				if (!Phase.bVisible)
				{
					continue;
				}
				const FVector2f Origin(View.X - Safe.Right - Layout::ToastW + (1.0f - Phase.Slide) * 80.0f, Safe.Top + 52.0f + static_cast<float>(Slot) * (Layout::ToastH + Layout::ToastGap));
				PaintToast(OutDrawElements, Layer, G, Entry, Origin, Phase.Alpha);
				Layer += 4;
				++Slot;
			}
		}

		// ---- banner (upper third)
		for (const Logic::FNotificationChannel::FEntry& Entry : Banners.GetVisible())
		{
			const Logic::FPhase Phase = Logic::NotificationPhase(Logic::FNotificationChannel::AgeOf(Entry, Now), Entry.HoldSec);
			if (!Phase.bVisible)
			{
				continue;
			}
			const float A = Phase.Alpha;
			const FVector2f Size(760.0f, 132.0f);
			const FVector2f Origin((View.X - Size.X) * 0.5f, View.Y * 0.20f + (1.0f - Phase.Slide) * 30.0f);
			DrawBox(OutDrawElements, Layer, G, Origin, Size, Brushes::Panel(), Color::WithAlpha(Color::Glass(), A));
			DrawBox(OutDrawElements, Layer + 1, G, Origin + FVector2f(Size.X * 0.5f - 70.0f, Size.Y - 11.0f), FVector2f(140.0f, 4.0f), Brushes::Pill(), Color::WithAlpha(Entry.Data.Color, A));
			PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f, 14.0f), FitText(Entry.Data.Title.ToString().ToUpper(), Font(46, true), Size.X - 60.0f), Font(46, true), Color::WithAlpha(Color::Chalk(), A), ETextAnchor::Center, true);
			PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f, 76.0f), FitText(Entry.Data.Body.ToString(), Font(22), Size.X - 60.0f), Font(22), Color::WithAlpha(Color::Dim(), A), ETextAnchor::Center);
			Layer += 5;
		}

		// ---- result card (centre)
		for (const Logic::FNotificationChannel::FEntry& Entry : Cards.GetVisible())
		{
			const Logic::FPhase Phase = Logic::NotificationPhase(Logic::FNotificationChannel::AgeOf(Entry, Now), Entry.HoldSec);
			if (!Phase.bVisible)
			{
				continue;
			}
			const FRoamNotification& N = Entry.Data;
			const float A = Phase.Alpha;
			const FVector2f Size(560.0f, 360.0f);
			const FVector2f Origin((View.X - Size.X) * 0.5f, (View.Y - Size.Y) * 0.5f + (1.0f - Phase.Slide) * 40.0f);
			DrawBox(OutDrawElements, Layer, G, Origin, Size, Brushes::Panel(), Color::WithAlpha(FLinearColor(0.025f, 0.035f, 0.055f, 0.86f), A));
			DrawBox(OutDrawElements, Layer + 1, G, Origin + FVector2f(0.0f, 0.0f), FVector2f(Size.X, 8.0f), Brushes::Flat(), Color::WithAlpha(N.Color, A));
			PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f, 28.0f), FitText(N.Title.ToString().ToUpper(), Font(30, true), Size.X - 60.0f), Font(30, true), Color::WithAlpha(Color::Teal(), A), ETextAnchor::Center);
			PaintStars(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f - 76.0f, 112.0f), 29.0f, 76.0f, N.Stars, 3, A);
			if (!N.Value.IsEmpty())
			{
				PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f, 164.0f), N.Value.ToString(), Font(72, true), Color::WithAlpha(Color::Chalk(), A), ETextAnchor::Center, true);
			}
			PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f, 266.0f), FitText(N.Body.ToString(), Font(22), Size.X - 60.0f), Font(22), Color::WithAlpha(Color::Dim(), A), ETextAnchor::Center);
			if (N.bNewBest)
			{
				DrawBox(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X * 0.5f - 76.0f, 306.0f), FVector2f(152.0f, 32.0f), Brushes::Pill(), Color::WithAlpha(Color::Orange(), A));
				PaintText(OutDrawElements, Layer + 3, G, Origin + FVector2f(Size.X * 0.5f, 309.0f), TEXT("NEW BEST"), Font(20, true), FLinearColor(0.05f, 0.05f, 0.06f, A), ETextAnchor::Center);
			}
			Layer += 6;
		}
	}
	return Layer + 1;
}

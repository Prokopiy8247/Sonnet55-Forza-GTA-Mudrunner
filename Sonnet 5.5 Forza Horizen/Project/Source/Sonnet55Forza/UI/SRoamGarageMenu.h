// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Data/RoamCarDefinition.h"
#include "UI/RoamMenus.h"
#include "Widgets/DeclarativeSyntaxSupport.h"
#include "Widgets/SCompoundWidget.h"

class ARoamVehicle;
class SScrollBox;
class SVerticalBox;
class SWidgetSwitcher;
class UGameInstance;

/**
 * Garage (F1 / Tab): three tabs.
 *   CARS      the cars of URoamCarCatalog with class badge + PI, drivetrain, six stat bars (from URoamCarDefinition::ComputePerformance),
 *             power / mass numbers; SELECT switches the car through ARoamGameMode::SpawnPlayerCarAtCurrent.
 *   PAINT     body / accent / wheel colour (12 presets + RGB sliders), finish, stripe style, wheel style -> ARoamVehicle::SetPaint + profile.
 *   UPGRADES  the upgrade slots of the car with tier buttons and a stat-delta preview. The tiers are stored in the profile and passed to
 *             ARoamVehicle::SetUpgrades; what a tier does to the physics is the vehicle owner's hook, so the deltas are a data-only preview.
 * Navigation: mouse, Up/Down + Enter (cars), Q/E or LB/RB (tabs), Tab/F1/Esc/gamepad B close.
 */
class SRoamGarageMenu : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamGarageMenu) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UGameInstance>, GameInstance)
		SLATE_EVENT(FSimpleDelegate, OnCloseRequested)
		SLATE_EVENT(FSimpleDelegate, OnToggleConsole)
		SLATE_EVENT(FSimpleDelegate, OnToggleDebug)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

	/** The panel was opened: re-read catalog, current car, paint and upgrades. */
	void OnOpened();
	TSharedPtr<SWidget> GetFocusWidget() const;
	/** "cars" | "paint" | "upgrades" (console command garage.tab, automation). Returns false for an unknown name. */
	bool SetTabByName(const FString& Name);

	virtual bool SupportsKeyboardFocus() const override { return true; }
	virtual FReply OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent) override;

private:
	enum class ETab : uint8 { Cars = 0, Paint, Upgrades };
	enum class EPaintTarget : uint8 { Body = 0, Accent, Wheels };

	struct FCarEntry
	{
		TWeakObjectPtr<URoamCarDefinition> Definition;
		FName CarId;
		FString Name;
		FRoamCarPerformance Performance;
		RoamMenus::FStatValues Stats;
	};

	// ---- data -----------------------------------------------------------------------------------------------------
	ARoamVehicle* GetVehicle() const;
	URoamCarDefinition* GetCurrentDefinition() const;
	void RebuildCars();
	FCarEntry MakeEntry(URoamCarDefinition* Definition);
	const FCarEntry* GetPreview() const { return Entries.IsValidIndex(PreviewIndex) ? &Entries[PreviewIndex] : nullptr; }
	bool IsCurrent(int32 Index) const;
	void SetPreview(int32 Index);
	void SelectCar(int32 Index);

	// ---- tabs ------------------------------------------------------------------------------------------------------
	void SetTab(ETab NewTab);
	void StepTab(int32 Direction);
	TSharedRef<SWidget> BuildCarsTab();
	TSharedRef<SWidget> BuildPaintTab();
	TSharedRef<SWidget> BuildUpgradesTab();
	TSharedRef<SWidget> BuildCarRow(int32 Index);
	TAttribute<FText> PreviewText(TFunction<FString(const FCarEntry&, const URoamCarDefinition&)> Fn) const;

	// ---- paint -----------------------------------------------------------------------------------------------------
	FRoamPaint GetPaint() const;
	void ApplyPaint(const FRoamPaint& NewPaint);
	FLinearColor GetTargetColor() const;
	void SetTargetColor(const FLinearColor& Color);
	float GetChannel(int32 Channel) const;
	void SetChannel(int32 Channel, float Value01);

	// ---- upgrades --------------------------------------------------------------------------------------------------
	void RebuildUpgrades();
	int32 GetTier(FName SlotId) const;
	void ChangeTier(int32 SlotIndex, int32 Delta);
	RoamMenus::FStatValues GetUpgradeDelta() const;
	int32 EstimatePerformanceIndex() const;

	TWeakObjectPtr<UGameInstance> GameInstance;
	FSimpleDelegate OnCloseRequested;
	FSimpleDelegate OnToggleConsole;
	FSimpleDelegate OnToggleDebug;

	ETab Tab = ETab::Cars;
	EPaintTarget PaintTarget = EPaintTarget::Body;

	TArray<FCarEntry> Entries;
	TMap<FName, FCarEntry> EntryCache;
	int32 PreviewIndex = 0;

	TSharedPtr<SVerticalBox> CarRows;
	TSharedPtr<SVerticalBox> UpgradeRows;
	TSharedPtr<SWidgetSwitcher> Switcher;
	TSharedPtr<SWidget> PaintFocus;
	TSharedPtr<SWidget> UpgradeFocus;

	TArray<FRoamUpgradeSlot> Slots;
	bool bDefaultSlots = false;
	RoamMenus::FStatValues CurrentBase;
	float CurrentScore = 0.0f;
};

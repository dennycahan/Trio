import Foundation
import Testing
@testable import Trio

@Suite("DetermineBasalAggressiveDosingTests") struct DetermineBasalAggressiveDosingTests {
    private func callCalculateInsulinRequired(
        minForecastGlucose: Decimal,
        eventualGlucose: Decimal,
        targetGlucose: Decimal,
        adjustedSensitivity: Decimal,
        maxIob: Decimal,
        currentIob: Decimal
    ) -> (insulinRequired: Decimal, determination: Determination) {
        let determination = Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        return DosingEngine.calculateInsulinRequired(
            minForecastGlucose: minForecastGlucose,
            eventualGlucose: eventualGlucose,
            targetGlucose: targetGlucose,
            adjustedSensitivity: adjustedSensitivity,
            maxIob: maxIob,
            currentIob: currentIob,
            determination: determination
        )
    }

    @Test("should calculate insulin required based on minPredBG when it is lower") func testCalculateBasedOnMinForecast() {
        // minPredBG (150) < eventualBG (180)
        // (150 - 100) / 50 = 1.0 U
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 150,
            eventualGlucose: 180,
            targetGlucose: 100,
            adjustedSensitivity: 50,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == 1.0)
        #expect(result.determination.insulinReq == 1.0)
    }

    @Test("should calculate insulin required based on eventualBG when it is lower") func testCalculateBasedOnEventual() {
        // eventualBG (140) < minPredBG (160)
        // (140 - 100) / 40 = 1.0 U
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 160,
            eventualGlucose: 140,
            targetGlucose: 100,
            adjustedSensitivity: 40,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == 1.0)
        #expect(result.determination.insulinReq == 1.0)
    }

    @Test("should cap insulinReq at max_iob - current_iob") func testCapAtMaxIOB() {
        // (200 - 100) / 20 = 5.0 U required
        // max_iob (3) - current_iob (1) = 2.0 U available space
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 200,
            eventualGlucose: 200,
            targetGlucose: 100,
            adjustedSensitivity: 20,
            maxIob: 3,
            currentIob: 1
        )
        #expect(result.insulinRequired == 2.0)
        #expect(result.determination.reason.contains("max_iob 3"))
    }

    @Test("should not cap if insulinReq is within max_iob limits") func testNoCapWithinLimits() {
        // (140 - 100) / 20 = 2.0 U required
        // max_iob (5) - current_iob (1) = 4.0 U available space
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 140,
            eventualGlucose: 140,
            targetGlucose: 100,
            adjustedSensitivity: 20,
            maxIob: 5,
            currentIob: 1
        )
        #expect(result.insulinRequired == 2.0)
        #expect(!result.determination.reason.contains("max_iob"))
    }

    @Test("should handle negative IOB increasing available space") func testNegativeIOBIncreasesSpace() {
        // (200 - 100) / 20 = 5.0 U required
        // max_iob (3) - current_iob (-1) = 4.0 U available space
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 200,
            eventualGlucose: 200,
            targetGlucose: 100,
            adjustedSensitivity: 20,
            maxIob: 3,
            currentIob: -1
        )
        #expect(result.insulinRequired == 4.0)
        #expect(result.determination.reason.contains("max_iob 3"))
    }

    @Test("should handle negative insulinReq correctly") func testNegativeInsulinReq() {
        // (90 - 100) / 50 = -0.2 U
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 90,
            eventualGlucose: 95,
            targetGlucose: 100,
            adjustedSensitivity: 50,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == -0.2)
    }

    @Test("should round calculations to 2 decimal places") func testRounding() {
        // (133 - 100) / 30 = 1.1
        let result = callCalculateInsulinRequired(
            minForecastGlucose: 133,
            eventualGlucose: 133,
            targetGlucose: 100,
            adjustedSensitivity: 30,
            maxIob: 5,
            currentIob: 0
        )
        #expect(result.insulinRequired == 1.1)
    }

    private func callDetermineSMBDelivery(
        insulinRequired: Decimal,
        microBolusAllowed: Bool = true,
        smbIsEnabled: Bool = true,
        currentGlucose: Decimal = 120,
        threshold: Decimal = 60,
        profile: Profile,
        mealData: ComputedCarbs = ComputedCarbs(
            carbs: 0,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: 0
        ),
        iobData: [IobResult],
        trioCustomOrefVariables: TrioCustomOrefVariables? = nil,
        adjustedCarbRatio: Decimal = 10,
        basal: Decimal = 1.0,
        naiveEventualGlucose: Decimal = 120,
        minIOBForecastedGlucose: Decimal = 120
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        let determination = Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        var finalTrioCustomOrefVariables: TrioCustomOrefVariables
        if let customOrefVars = trioCustomOrefVariables {
            finalTrioCustomOrefVariables = customOrefVars
        } else {
            finalTrioCustomOrefVariables = TrioCustomOrefVariables(
                average_total_data: 0,
                weightedAverage: 0,
                currentTDD: 0,
                past2hoursAverage: 0,
                date: Date(),
                overridePercentage: 100,
                useOverride: false,
                duration: 0,
                unlimited: false,
                overrideTarget: 0,
                smbIsOff: false,
                advancedSettings: false,
                isfAndCr: false,
                isf: false,
                cr: false,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: 30,
                uamMinutes: 30
            )
        }

        return try DosingEngine.determineSMBDelivery(
            insulinRequired: insulinRequired,
            microBolusAllowed: microBolusAllowed,
            smbIsEnabled: smbIsEnabled,
            currentGlucose: currentGlucose,
            threshold: threshold,
            profile: profile,
            trioCustomOrefVariables: finalTrioCustomOrefVariables,
            mealData: mealData,
            iobData: iobData,
            currentTime: Date(),
            targetGlucose: profile.targetBg ?? 100,
            naiveEventualGlucose: naiveEventualGlucose,
            minIOBForecastedGlucose: minIOBForecastedGlucose,
            adjustedSensitivity: profile.sens ?? 40,
            adjustedCarbRatio: adjustedCarbRatio,
            basal: basal,
            determination: determination
        )
    }

    @Test("should calculate correct microbolus with rounding") func testMicroBolusRounding() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000) // 10 minutes ago

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // insulinReq = 1.55
        // maxBolus = 1.0 * 30/60 = 0.5
        // smb = min(1.55 * 0.5, 0.5) = min(0.775, 0.5) = 0.5
        // 0.5 is already rounded.
        // Let's try a case where maxBolus is higher.

        profile.maxSMBBasalMinutes = 60
        // maxBolus = 1.0 * 60/60 = 1.0
        // smb = min(1.55 * 0.5, 1.0) = 0.775
        // rounded down to 0.1 increment: 0.7

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.55,
            profile: profile,
            iobData: iobData
        )

        #expect(result.determination.units == 0.7)
    }

    @Test("should apply override factor to maxBolus") func testOverrideFactorMaxBolus() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000) // 10 minutes ago

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // Override factor 2.0 (200%)
        // maxBolus = 1.0 * 2.0 * 30/60 = 1.0
        // insulinReq = 3.0
        // smb = min(3.0 * 0.5, 1.0) = min(1.5, 1.0) = 1.0

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 200, // 2.0 * 100
            useOverride: true,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 1.0)
    }

    @Test(
        "should override smbMinutes and uamMinutes when useOverride and advancedSettings are true"
    ) func testOverrideSmbUamMinutes() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // 0.5U
        profile.maxUAMSMBBasalMinutes = 30 // 0.5U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)

        // Case 1: Regular SMB (IOB <= mealInsulinReq)
        // insulinReq = 3.0
        // maxBolus should be 1.0 (60 mins override) instead of 0.5 (30 mins profile)
        // smb = min(3.0 * 0.5, 1.0) = 1.0

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 100,
            useOverride: true,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: true,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 60,
            uamMinutes: 60
        )

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 1.0)

        // Case 2: UAM SMB (IOB > mealInsulinReq)
        // mealCOB = 10, CR = 10 => mealInsulinReq = 1.0
        // iob = 1.5
        let mealData = ComputedCarbs(
            carbs: 0,
            mealCOB: 10,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: 0
        )
        let uamIobData = [IobResult(
            iob: 1.5,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        let uamResult = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            mealData: mealData,
            iobData: uamIobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(uamResult.determination.units == 1.0)
    }

    @Test(
        "should not override smbMinutes and uamMinutes when advancedSettings is false"
    ) func testNoOverrideWhenAdvancedSettingsFalse() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // 0.5U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 100,
            useOverride: true,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 60,
            uamMinutes: 60
        )

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // insulinReq = 3.0
        // maxBolus should be 0.5 (30 mins from profile), ignoring override 60 because advancedSettings is false
        // smb = min(1.5, 0.5) = 0.5

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 0.5)
    }

    @Test("should use overridePercentage from custom vars if provided") func testOverridePercentageFromCustomVars() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // 0.5U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 40
        profile.targetBg = 100

        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)

        var customOrefVars = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: Date(),
            overridePercentage: 200, // 200%
            useOverride: true,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // maxBolus = 1.0 * 2.0 * 30/60 = 1.0
        // insulinReq = 3.0
        // smb = min(3.0 * 0.5, 1.0) = 1.0

        let result = try callDetermineSMBDelivery(
            insulinRequired: 3.0,
            profile: profile,
            iobData: iobData,
            trioCustomOrefVariables: customOrefVars
        )

        #expect(result.determination.units == 1.0)
    }

    @Test("should not bolus if within SMB interval") func testSMBInterval() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.smbInterval = 3
        profile.sens = 40
        profile.targetBg = 100

        // Last bolus 1 minute ago
        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now,
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        // Setup conditions where temp basal is required so it returns true, but NO units
        // worstCase > 0 => low pred
        // (100 - (90+90)/2) / 40 = 0.25
        // duration = 60 * 0.25 / 1 = 15m
        // 15m -> <30m -> sets smbLowTempReq -> returns true

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 90,
            minIOBForecastedGlucose: 90
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.units == nil)
        #expect(result.determination.reason.contains("Waiting"))
    }

    @Test("should return false if SMB conditions not met") func testGuardConditions() throws {
        var profile = Profile()
        profile.currentBasal = 1.0

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // bg (100) < threshold (110)
        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            currentGlucose: 100,
            threshold: 110,
            profile: profile,
            iobData: iobData
        )

        #expect(result.shouldSetTempBasal == false)
    }

    private func callDetermineHighTempBasal(
        insulinRequired: Decimal,
        basal: Decimal,
        profile: Profile,
        currentTemp: TempBasal
    ) throws -> Determination {
        let determination = Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: nil
        )

        return try DosingEngine.determineHighTempBasal(
            insulinRequired: insulinRequired,
            basal: basal,
            profile: profile,
            currentTemp: currentTemp,
            determination: determination
        )
    }

    @Test("should set high temp if no temp is running") func testSetHighTempNoTemp() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0 // Unused by logic but good for completeness

        // insulinReq = 1.0. basal = 1.0. rate = 1.0 + 2*1.0 = 3.0.
        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 3.0)
        #expect(result.duration == 30)
        #expect(result.reason.contains("no temp, setting 3U/hr"))
    }

    @Test("should cap rate at maxSafeBasal") func testCapAtMaxSafeBasal() throws {
        var profile = Profile()
        profile.maxBasal = 2.0 // Restrict max basal
        profile.maxDailyBasal = 2.0
        profile.currentBasalSafetyMultiplier = 4
        profile.maxDailySafetyMultiplier = 3
        profile.currentBasal = 1.0

        // insulinReq = 1.0. basal = 1.0. rate = 3.0. Max = 2.0.
        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 2.0)
        #expect(result.reason.contains("adj. req. rate: 3"))
        #expect(result.reason.contains("maxSafeBasal: 2"))
    }

    @Test("should reduce temp if current temp delivers >2x required insulin") func testReduceTempIfScheduledTooHigh() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0

        // insulinReq = 0.5. 2x = 1.0 U.
        // basal = 1.0. rate = 1.0 + 1.0 = 2.0.
        // Current temp: rate 4.0, duration 30m.
        // insulinScheduled = 30 * (4.0 - 1.0) / 60 = 1.5 U.

        let result = try callDetermineHighTempBasal(
            insulinRequired: 0.5,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 4.0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 2.0)
        #expect(result.reason.contains("> 2 * insulinReq"))
    }

    @Test("should do nothing if current temp is sufficient") func testDoNothingIfSufficient() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0

        // insulinReq = 1.0. rate = 3.0.
        // Current temp: rate 3.0, duration 30m.

        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 3.0, temp: .absolute, timestamp: Date())
        )

        // Should return determination without setting rate/duration (nil implies unchanged in this context check?)
        // Wait, determineHighTempBasal returns a Determination. If it calls setTempBasal, rate/duration are set.
        // If it falls through, it returns 'determination' (which has nil rate/duration).

        #expect(result.rate == nil)
        #expect(result.duration == nil)
        #expect(result.reason.contains("temp 3 >~ req 3U/hr"))
    }

    @Test("should set new temp if current temp is insufficient") func testSetNewTempIfInsufficient() throws {
        var profile = Profile()
        profile.maxBasal = 5.0
        profile.maxDailyBasal = 5.0
        profile.currentBasal = 1.0

        // insulinReq = 1.0. rate = 3.0.
        // Current temp: rate 2.0.

        let result = try callDetermineHighTempBasal(
            insulinRequired: 1.0,
            basal: 1.0,
            profile: profile,
            currentTemp: TempBasal(duration: 30, rate: 2.0, temp: .absolute, timestamp: Date())
        )

        #expect(result.rate == 3.0)
        #expect(result.duration == 30)
        #expect(result.reason.contains("temp 2<3U/hr"))
    }

    @Test("should set 30m zero temp if durationReq is between 30 and 45") func testSet30mZeroTemp() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq ~ 35
        // duration = 60 * worst / basal => 35 = 60 * worst / 1.0 => worst = 0.583
        // worst = (100 - avg)/50 => avg = 70.85

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 70.85,
            minIOBForecastedGlucose: 70.85
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0)
        #expect(result.determination.duration == 30)
    }

    @Test("should set 60m zero temp if durationReq is > 45") func testSet60mZeroTemp() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq ~ 50
        // 50 = 60 * worst / 1.0 => worst = 0.833
        // worst = (100 - avg)/50 => avg = 58.35

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 58.35,
            minIOBForecastedGlucose: 58.35
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0)
        #expect(result.determination.duration == 60)
    }

    @Test("should cap zero temp duration at 60m") func testCapZeroTempAt60m() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq > 75
        // 100 = 60 * worst / 1.0 => worst = 1.66
        // worst = (100 - avg)/50 => avg = 17

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            naiveEventualGlucose: 17,
            minIOBForecastedGlucose: 17
        )

        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0)
        #expect(result.determination.duration == 60)
    }

    @Test("should set low temp if durationReq < 30") func testSetLowTemp() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // worstCaseInsulinReq needs to result in durationReq = 15
        // 15 = 60 * worst / 1.0 => worst = 0.25
        // worst = (100 - avg)/50 => avg = 87.5

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            basal: 1.0,
            naiveEventualGlucose: 87.5,
            minIOBForecastedGlucose: 87.5
        )

        // Rate = basal * 15/30 = 1.0 * 0.5 = 0.5
        #expect(result.shouldSetTempBasal == true)
        #expect(result.determination.rate == 0.5)
        #expect(result.determination.duration == 30)
    }

    @Test("should not set temp if insulinReq > 0 but microBolus < increment") func testNoTempIfMicroBolusTooSmall() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // insulinReq = 0.05 (positive but small)
        // microBolus < 0.1
        // durationReq = 15m (via predictions)

        let result = try callDetermineSMBDelivery(
            insulinRequired: 0.05,
            profile: profile,
            iobData: iobData,
            basal: 1.0,
            naiveEventualGlucose: 87.5,
            minIOBForecastedGlucose: 87.5
        )

        #expect(result.shouldSetTempBasal == false)
    }

    @Test("should not set temp if durationReq <= 0") func testNoTempIfDurationReqNegative() throws {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = 0.1
        profile.sens = 50
        profile.targetBg = 100

        let dummyIobWithZeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date()
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: Date(),
            iobWithZeroTemp: dummyIobWithZeroTemp,
            lastBolusTime: nil,
            lastTemp: nil
        )]

        // High predictions => negative worstCase => negative durationReq
        // avg = 150 > target 100

        let result = try callDetermineSMBDelivery(
            insulinRequired: 1.0,
            profile: profile,
            iobData: iobData,
            basal: 1.0,
            naiveEventualGlucose: 150,
            minIOBForecastedGlucose: 150
        )

        #expect(result.shouldSetTempBasal == false)
    }
}

// MARK: - IOB limit (Trio-only, opt-in): insulin on board limits insulinReq

/// Exact decimal; a Decimal float literal goes through Double (0.92 becomes 0.9200000000000002048)
private func dec(_ string: String) -> Decimal {
    Decimal(string: string)!
}

private func blankDetermination(reason: String = "") -> Determination {
    Determination(
        id: UUID(),
        reason: reason,
        units: nil,
        insulinReq: nil,
        eventualBG: nil,
        sensitivityRatio: nil,
        rate: nil,
        duration: nil,
        iob: nil,
        cob: nil,
        predictions: nil,
        deliverAt: nil,
        carbsReq: nil,
        temp: nil,
        bg: nil,
        reservoir: nil,
        isf: nil,
        timestamp: nil,
        tdd: nil,
        current_target: nil,
        minDelta: nil,
        expectedDelta: nil,
        minGuardBG: nil,
        minPredBG: nil,
        threshold: nil,
        carbRatio: nil,
        received: nil
    )
}

private let noCarbs = ComputedCarbs(
    carbs: 0,
    mealCOB: 0,
    currentDeviation: 0,
    maxDeviation: 0,
    minDeviation: 0,
    slopeFromMaxDeviation: 0,
    slopeFromMinDeviation: 0,
    allDeviations: [],
    lastCarbTime: 0
)

@Suite("IOB limit: insulinReq") struct IobLimitInsulinRequiredTests {
    /// naive eventual glucose exactly as DeterminationGenerator computes it when IOB > 0
    private func naive(glucose: Decimal, iob: Decimal, sens: Decimal) -> Decimal {
        (glucose - iob * sens).jsRounded()
    }

    /// `stockGlucose` is min(minPredBG, eventualBG), which sets the stock value
    private func requirement(
        stockGlucose: Decimal,
        naiveEventualGlucose: Decimal,
        targetGlucose: Decimal = 90,
        adjustedSensitivity: Decimal = 25,
        maxIob: Decimal = 10,
        currentIob: Decimal,
        limit: Bool = true,
        reason: String = ""
    ) -> DosingEngine.InsulinRequirement {
        DosingEngine.calculateInsulinRequired(
            minForecastGlucose: stockGlucose,
            eventualGlucose: stockGlucose,
            targetGlucose: targetGlucose,
            adjustedSensitivity: adjustedSensitivity,
            maxIob: maxIob,
            currentIob: currentIob,
            naiveEventualGlucose: naiveEventualGlucose,
            iobLimitsInsulinReq: limit,
            determination: blankDetermination(reason: reason)
        )
    }

    @Test("Worked example: glucose 130, IOB 3.0, ISF 25: naive 55, room -1.4, insulinReq 0") func workedExample130() {
        let naiveGlucose = naive(glucose: 130, iob: 3.0, sens: 25)
        #expect(naiveGlucose == 55)
        let result = requirement(stockGlucose: 150, naiveEventualGlucose: naiveGlucose, currentIob: 3.0)
        #expect(result.stockInsulinRequired == 2.4)
        #expect(result.insulinRequired == 0)
        #expect(result.determination.insulinReq == 0)
        #expect(result.determination.reason == "IOB limit 2.4→0, ")
    }

    @Test(
        "Worked example: glucose 167, IOB 3.74: naive 74 (stock rounds 73.5), insulinReq 0 where stock asks 2.08"
    ) func workedExample167() {
        let naiveGlucose = naive(glucose: 167, iob: 3.74, sens: 25)
        #expect(naiveGlucose == 74)
        let result = requirement(stockGlucose: 142, naiveEventualGlucose: naiveGlucose, currentIob: 3.74)
        #expect(result.stockInsulinRequired == 2.08)
        #expect(result.insulinRequired == 0)
        #expect(result.determination.insulinReq == 0)
        #expect(result.determination.reason == "IOB limit 2.08→0, ")
    }

    @Test("Worked example: glucose 195, IOB 3.3: naive 113 (stock rounds 112.5), room 0.92") func workedExample195() {
        let naiveGlucose = naive(glucose: 195, iob: 3.3, sens: 25)
        #expect(naiveGlucose == 113)
        #expect(
            DosingEngine.insulinRoomLeftByIob(naiveEventualGlucose: naiveGlucose, targetGlucose: 90, adjustedSensitivity: 25) ==
                dec("0.92")
        )

        let limited = requirement(stockGlucose: 152.5, naiveEventualGlucose: naiveGlucose, currentIob: 3.3)
        #expect(limited.stockInsulinRequired == 2.5)
        #expect(limited.insulinRequired == dec("0.92"))
        #expect(limited.determination.insulinReq == dec("0.92"))
        #expect(limited.determination.reason == "IOB limit 2.5→0.92, ")

        // stock below the room stands
        let below = requirement(stockGlucose: 110, naiveEventualGlucose: naiveGlucose, currentIob: 3.3)
        #expect(below.insulinRequired == 0.8)
        #expect(below.determination.reason == "")
    }

    @Test("Worked example: glucose 220, IOB 1.0: room 4.2, stock applies unless it asks for more") func workedExample220() {
        let naiveGlucose = naive(glucose: 220, iob: 1.0, sens: 25)
        #expect(naiveGlucose == 195)

        let asksLess = requirement(stockGlucose: 165, naiveEventualGlucose: naiveGlucose, currentIob: 1.0)
        #expect(asksLess.stockInsulinRequired == 3)
        #expect(asksLess.insulinRequired == 3)
        #expect(asksLess.determination.reason == "")

        let asksMore = requirement(stockGlucose: 215, naiveEventualGlucose: naiveGlucose, currentIob: 1.0)
        #expect(asksMore.stockInsulinRequired == 5)
        #expect(asksMore.insulinRequired == 4.2)
        #expect(asksMore.determination.reason == "IOB limit 5→4.2, ")
    }

    @Test("Negative IOB: naive sits above glucose, the room grows, and stock beyond it is still limited") func negativeIob() {
        // for IOB <= 0 the generator uses min(profile ISF, adjusted ISF); both 25 here
        let naiveGlucose = (Decimal(140) - Decimal(-0.8) * 25).jsRounded()
        #expect(naiveGlucose == 160)

        let limited = requirement(stockGlucose: 190, naiveEventualGlucose: naiveGlucose, currentIob: -0.8)
        #expect(limited.stockInsulinRequired == 4)
        #expect(limited.insulinRequired == 2.8)
        #expect(limited.determination.reason == "IOB limit 4→2.8, ")

        let within = requirement(stockGlucose: 140, naiveEventualGlucose: naiveGlucose, currentIob: -0.8)
        #expect(within.insulinRequired == 2)
        #expect(within.determination.reason == "")
    }

    @Test("max_iob clamps first, the IOB limit after it, and its marker follows max_iob") func maxIobThenLimit() {
        // stock (200 - 90) / 25 = 4.4, clamped to max_iob 3 - IOB 1.2 = 1.8
        let limited = requirement(stockGlucose: 200, naiveEventualGlucose: 130, maxIob: 3, currentIob: 1.2)
        #expect(limited.stockInsulinRequired == 1.8)
        #expect(limited.insulinRequired == 1.6) // (130 - 90) / 25
        #expect(limited.determination.insulinReq == 1.6)
        #expect(limited.determination.reason == "max_iob 3, IOB limit 1.8→1.6, ")

        let clampedBelowRoom = requirement(stockGlucose: 200, naiveEventualGlucose: 160, maxIob: 3, currentIob: 1.2)
        #expect(clampedBelowRoom.insulinRequired == 1.8)
        #expect(clampedBelowRoom.determination.reason == "max_iob 3, ")
    }

    @Test("A zero or negative stock insulinReq is never changed") func nonPositiveStockUntouched() {
        let negative = requirement(stockGlucose: 85, naiveEventualGlucose: 40, currentIob: 2)
        #expect(negative.insulinRequired == -0.2)
        #expect(negative.determination.insulinReq == -0.2)
        #expect(negative.determination.reason == "")

        let zero = requirement(stockGlucose: 90, naiveEventualGlucose: 40, currentIob: 2)
        #expect(zero.insulinRequired == 0)
        #expect(zero.determination.reason == "")
    }

    @Test("Room is floored to 2 decimals: never above the exact value, never more than 0.01 below it") func roomFloored() {
        // 23 / 30 = 0.766...: floored, not rounded up to 0.77
        #expect(DosingEngine.insulinRoomLeftByIob(naiveEventualGlucose: 113, targetGlucose: 90, adjustedSensitivity: 30) == 0.76)
        // 30 / 20.8 = 1.442...
        #expect(
            DosingEngine
                .insulinRoomLeftByIob(naiveEventualGlucose: 120, targetGlucose: 90, adjustedSensitivity: 20.8) == 1.44
        )
        #expect(DosingEngine.insulinRoomLeftByIob(naiveEventualGlucose: 90, targetGlucose: 90, adjustedSensitivity: 25) == 0)
        #expect(DosingEngine.insulinRoomLeftByIob(naiveEventualGlucose: 55, targetGlucose: 90, adjustedSensitivity: 25) == 0)

        let sensitivities: [Decimal] = [17.5, 20.8, 25, 31.3, 41.7, 50]
        for naiveGlucose in 40 ... 300 {
            for sens in sensitivities {
                let exact = max(0, (Decimal(naiveGlucose) - 90) / sens)
                let room = DosingEngine.insulinRoomLeftByIob(
                    naiveEventualGlucose: Decimal(naiveGlucose),
                    targetGlucose: 90,
                    adjustedSensitivity: sens
                )
                #expect(room <= exact, "naive \(naiveGlucose) sens \(sens)")
                #expect(exact - room < 0.01, "naive \(naiveGlucose) sens \(sens)")
                #expect(room == room.rounded(scale: 2), "naive \(naiveGlucose) sens \(sens)")
            }
        }
    }

    @Test(
        "Preference off: identical to stock; on: exactly min(stock, room) with the room worked out by hand"
    ) func offIsStock() {
        let prefix = "Autosens ratio: 1, ISF: 25→25, COB: 0, Dev: 20, BGI: -2, CR: 10, Target: 90, minPredBG 120; "
        let stockGlucoses: [Decimal] = [40, 85, 90, 95, 133, 150, 200, 260]
        // room at target 90 and ISF 25, by hand: (naive - 90) / 25 floored to 2 decimals, 0 at or below target
        let rooms: [(naive: Decimal, room: Decimal)] = [
            (40, 0), (89, 0), (90, 0), (91, dec("0.04")), (113, dec("0.92")), (160, dec("2.8")), (300, dec("8.4"))
        ]
        let iobCases: [(maxIob: Decimal, iob: Decimal)] = [(10, 0), (3, 1.2), (2, -0.5), (0, 0)]
        var bound = 0
        for stockGlucose in stockGlucoses {
            for room in rooms {
                for iobCase in iobCases {
                    let label = "stock bg \(stockGlucose) naive \(room.naive) max_iob \(iobCase.maxIob) iob \(iobCase.iob)"
                    let (stockValue, stockDetermination) = DosingEngine.calculateInsulinRequired(
                        minForecastGlucose: stockGlucose,
                        eventualGlucose: stockGlucose + 10,
                        targetGlucose: 90,
                        adjustedSensitivity: 25,
                        maxIob: iobCase.maxIob,
                        currentIob: iobCase.iob,
                        determination: blankDetermination(reason: prefix)
                    )
                    for limit in [false, true] {
                        let result = DosingEngine.calculateInsulinRequired(
                            minForecastGlucose: stockGlucose,
                            eventualGlucose: stockGlucose + 10,
                            targetGlucose: 90,
                            adjustedSensitivity: 25,
                            maxIob: iobCase.maxIob,
                            currentIob: iobCase.iob,
                            naiveEventualGlucose: room.naive,
                            iobLimitsInsulinReq: limit,
                            determination: blankDetermination(reason: prefix)
                        )
                        let expected = limit ? min(stockValue, room.room) : stockValue
                        #expect(result.stockInsulinRequired == stockValue, "\(label)")
                        #expect(result.insulinRequired == expected, "\(label)")
                        #expect(result.determination.insulinReq == expected, "\(label)")
                        if expected == stockValue {
                            #expect(result.determination.reason == stockDetermination.reason, "\(label)")
                        } else {
                            bound += 1
                            let marker = "IOB limit \(stockValue)→\(expected), "
                            #expect(result.determination.reason == stockDetermination.reason + marker, "\(label)")
                        }
                    }
                }
            }
        }
        #expect(bound > 30)
    }

    @Test("Binding and non-binding cases worked out by hand, marker included") func byHand() {
        // stockGlucose is min(minPredBG, eventualBG); target 90, ISF 25
        let rows: [(stockGlucose: Decimal, naive: Decimal, maxIob: Decimal, iob: Decimal, insulinReq: String, reason: String)] = [
            (150, 113, 10, 0, "0.92", "IOB limit 2.4→0.92, "), // (150 - 90) / 25 = 2.4, room (113 - 90) / 25 = 0.92
            (200, 91, 10, 0, "0.04", "IOB limit 4.4→0.04, "), // 4.4, room 1 / 25 = 0.04
            (133, 89, 10, 0, "0", "IOB limit 1.72→0, "), // 1.72, naive below target
            (260, 160, 3, 1.2, "1.8", "max_iob 3, "), // 6.8 clamped to 3 - 1.2 = 1.8, below room 2.8
            (260, 113, 3, 1.2, "0.92", "max_iob 3, IOB limit 1.8→0.92, "),
            (95, 300, 10, 0, "0.2", ""), // 0.2, room 8.4
            (260, 300, 2, -0.5, "2.5", "max_iob 2, "), // clamped to 2 + 0.5 = 2.5, room 8.4
            (85, 40, 10, 0, "-0.2", "") // negative stock is left alone
        ]
        for row in rows {
            let result = requirement(
                stockGlucose: row.stockGlucose,
                naiveEventualGlucose: row.naive,
                maxIob: row.maxIob,
                currentIob: row.iob
            )
            #expect(result.insulinRequired == dec(row.insulinReq), "\(row)")
            #expect(result.determination.insulinReq == dec(row.insulinReq), "\(row)")
            #expect(result.determination.reason == row.reason, "\(row)")
        }
    }
}

@Suite("IOB limit: SMB low temp follows the stock decision") struct IobLimitSmbLowTempTests {
    private func smbProfile(increment: Decimal = 0.1, sens: Decimal = 50, target: Decimal = 100) -> Profile {
        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxSMBBasalMinutes = 30 // maxBolus 0.5 U
        profile.smbDeliveryRatio = 0.5
        profile.bolusIncrement = increment
        profile.sens = sens
        profile.targetBg = target
        profile.maxBasal = 3 // for determineHighTempBasal: max safe basal min(3, 3 x 1, 4 x 1) = 3
        profile.maxDailyBasal = 1.0
        return profile
    }

    private let noTemp = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())

    /// naive and minIOBPredBG of 87.5 against target 100 and ISF 50 ask for a 15-minute low temp: 0.5 U/h for 30 min
    private func deliver(
        insulinRequired: Decimal,
        stockInsulinRequired: Decimal?,
        profile: Profile? = nil,
        naiveEventualGlucose: Decimal = 87.5,
        minIOBForecastedGlucose: Decimal = 87.5
    ) throws -> (shouldSetTempBasal: Bool, determination: Determination) {
        let profile = profile ?? smbProfile()
        let now = Date()
        let lastBolusTime = UInt64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)
        let zeroTemp = IobResult.IobWithZeroTemp(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now
        )
        let iobData = [IobResult(
            iob: 0,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now,
            iobWithZeroTemp: zeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]
        return try DosingEngine.determineSMBDelivery(
            insulinRequired: insulinRequired,
            stockInsulinRequired: stockInsulinRequired,
            microBolusAllowed: true,
            smbIsEnabled: true,
            currentGlucose: 120,
            threshold: 60,
            profile: profile,
            trioCustomOrefVariables: ParityInputs.orefVariables(clock: now),
            mealData: noCarbs,
            iobData: iobData,
            currentTime: now,
            targetGlucose: profile.targetBg ?? 100,
            naiveEventualGlucose: naiveEventualGlucose,
            minIOBForecastedGlucose: minIOBForecastedGlucose,
            adjustedSensitivity: profile.sens ?? 50,
            adjustedCarbRatio: 10,
            basal: 1.0,
            determination: blankDetermination()
        )
    }

    @Test(
        "Limited to 0 where stock microbolused with a low temp: no microbolus, the same low temp"
    ) func limitedToZeroKeepsStockLowTemp() throws {
        let stock = try deliver(insulinRequired: 1.0, stockInsulinRequired: 1.0)
        #expect(stock.shouldSetTempBasal)
        #expect(stock.determination.units == 0.5)
        #expect(stock.determination.rate == 0.5)
        #expect(stock.determination.duration == 30)

        let limited = try deliver(insulinRequired: 0, stockInsulinRequired: 1.0)
        #expect(limited.shouldSetTempBasal)
        #expect(limited.determination.units == nil)
        #expect(limited.determination.rate == stock.determination.rate)
        #expect(limited.determination.duration == stock.determination.duration)
    }

    @Test(
        "Limited to a small positive value whose microbolus floors to 0: still the stock low temp, not a high temp"
    ) func smallLimitKeepsStockLowTemp() throws {
        // 0.15 x 0.5 = 0.075 floors to 0 at increment 0.1
        let limited = try deliver(insulinRequired: 0.15, stockInsulinRequired: 1.0)
        #expect(limited.shouldSetTempBasal)
        #expect(limited.determination.units == nil)
        #expect(limited.determination.rate == 0.5)
        #expect(limited.determination.duration == 30)

        // Deciding on the limited value alone drops the low temp and falls through to the high temp path,
        // which sets basal + 2 x 0.15 = 1.3 U/h: above stock's 0.5 U/h. Passing the stock value prevents this.
        let decidedOnLimited = try deliver(insulinRequired: 0.15, stockInsulinRequired: nil)
        #expect(!decidedOnLimited.shouldSetTempBasal)
        let highTemp = try DosingEngine.determineHighTempBasal(
            insulinRequired: 0.15,
            basal: 1.0,
            profile: smbProfile(),
            currentTemp: noTemp,
            determination: decidedOnLimited.determination
        )
        #expect(highTemp.rate == dec("1.3"))
        #expect(highTemp.duration == 30)
    }

    @Test(
        "Limited to 0 where stock's own microbolus was below one increment: no low temp, as stock, then basal"
    ) func stockMicrobolusTooSmallStaysWithoutLowTemp() throws {
        // stock: 0.15 x 0.5 = 0.075 floors to 0, so no SMB low temp; the high temp path sets 1 + 2 x 0.15
        let stock = try deliver(insulinRequired: 0.15, stockInsulinRequired: 0.15)
        #expect(!stock.shouldSetTempBasal)
        let stockHighTemp = try DosingEngine.determineHighTempBasal(
            insulinRequired: 0.15,
            basal: 1.0,
            profile: smbProfile(),
            currentTemp: noTemp,
            determination: stock.determination
        )
        #expect(stockHighTemp.rate == dec("1.3"))

        // limited to 0: no low temp either, and the high temp path with 0 sets a neutral temp at basal
        let limited = try deliver(insulinRequired: 0, stockInsulinRequired: 0.15)
        #expect(!limited.shouldSetTempBasal)
        #expect(limited.determination.units == nil)
        #expect(limited.determination.rate == nil)
        let limitedHighTemp = try DosingEngine.determineHighTempBasal(
            insulinRequired: 0,
            basal: 1.0,
            profile: smbProfile(),
            currentTemp: noTemp,
            determination: limited.determination
        )
        #expect(limitedHighTemp.rate == 1)
        #expect(limitedHighTemp.duration == 30)
    }

    @Test("Partly limited: smaller microbolus, the same low temp") func partlyLimited() throws {
        let limited = try deliver(insulinRequired: 0.45, stockInsulinRequired: 1.0)
        #expect(limited.shouldSetTempBasal)
        #expect(limited.determination.units == 0.2) // 0.45 x 0.5 = 0.225, floored to the 0.1 increment
        #expect(limited.determination.rate == 0.5)
        #expect(limited.determination.duration == 30)
        #expect(limited.determination.reason.contains("insulinReq 0.45"))
    }

    @Test(
        "Worked examples at increment 0.05: 195/3.3 microbolus 0.45 instead of 0.5; 167/3.74 none instead of 0.5"
    ) func workedExampleMicroboluses() throws {
        let profile = smbProfile(increment: 0.05, sens: 25, target: 90)

        // naive 113 > target: no low temp either way
        let stock195 = try deliver(
            insulinRequired: 2.5,
            stockInsulinRequired: 2.5,
            profile: profile,
            naiveEventualGlucose: 113,
            minIOBForecastedGlucose: 113
        )
        #expect(stock195.determination.units == 0.5)
        let limited195 = try deliver(
            insulinRequired: dec("0.92"),
            stockInsulinRequired: 2.5,
            profile: profile,
            naiveEventualGlucose: 113,
            minIOBForecastedGlucose: 113
        )
        #expect(limited195.determination.units == 0.45)
        #expect(!limited195.shouldSetTempBasal)

        // naive 74 < target: stock pairs its 0.5 U microbolus with a 30-minute zero temp, which stays
        let stock167 = try deliver(
            insulinRequired: 2.08,
            stockInsulinRequired: 2.08,
            profile: profile,
            naiveEventualGlucose: 74,
            minIOBForecastedGlucose: 74
        )
        #expect(stock167.determination.units == 0.5)
        #expect(stock167.determination.rate == 0)
        #expect(stock167.determination.duration == 30)
        let limited167 = try deliver(
            insulinRequired: 0,
            stockInsulinRequired: 2.08,
            profile: profile,
            naiveEventualGlucose: 74,
            minIOBForecastedGlucose: 74
        )
        #expect(limited167.determination.units == nil)
        #expect(limited167.determination.rate == 0)
        #expect(limited167.determination.duration == 30)
    }
}

/// The whole Swift pipeline the phone runs (ProfileGenerator, IobGenerator, MealGenerator,
/// DeterminationGenerator.generate) for one set of inputs, once with the preference off and once on.
/// Only `preferences.iobLimitsInsulinReq` differs between the two runs.
enum IobLimitPipeline {
    static let clock = Date.from(isoString: "2026-06-17T14:30:00+02:00")
    static let scheduledBasal: Decimal = 1.0
    static let isf: Decimal = 25
    static let target: Decimal = 90

    struct Case: CustomStringConvertible {
        var glucose = 160
        /// mg/dL per 5 minutes over the last hour; flat before that
        var delta = 5
        /// when set, the last 5-minute change, so the trace turns at the end
        var lastDelta: Int?
        var bolus: Decimal = 0
        var bolusMinutesAgo = 60
        /// hours of 0 U/h temps ending 30 minutes ago, for negative IOB
        var zeroTempHours = 0
        /// a 30-minute temp at this rate, started `runningTempMinutesAgo` ago, still running
        var runningTemp: Decimal?
        var runningTempMinutesAgo = 5
        var smb = true
        var tempTarget: Decimal?
        var overrideTarget: Decimal?
        var overridePercentage: Decimal = 100
        var autosensRatio: Decimal = 1
        var skipNeutralTemps = false
        /// replaces the generated description, e.g. with a parity scenario name
        var name: String?

        var description: String {
            if let name { return name }
            let temp = runningTemp.map { "\($0)U/h@-\(runningTempMinutesAgo)m" } ?? "none"
            let override = overrideTarget.map { "\($0)@\(overridePercentage)%" } ?? "-"
            return "bg \(glucose) delta \(delta) last \(lastDelta.map { "\($0)" } ?? "-") " +
                "bolus \(bolus)@-\(bolusMinutesAgo)m zeroTemp \(zeroTempHours)h temp \(temp) " +
                "smb \(smb) tt \(tempTarget.map { "\($0)" } ?? "-") override \(override) autosens \(autosensRatio) " +
                "skipNeutral \(skipNeutralTemps)"
        }
    }

    struct Outcome {
        let determination: Determination
        let currentTemp: TempBasal
        let profile: Profile
        let orefVariables: TrioCustomOrefVariables

        var units: Decimal { determination.units ?? 0 }

        var scheduledBasal: Decimal { profile.currentBasal ?? 0 }

        /// Rate the pump runs right after this determination is enacted. No new temp (rate nil) leaves the
        /// running temp on, or scheduled basal when none runs; a 0-minute temp cancels to scheduled basal.
        var effectiveRate: Decimal {
            guard let rate = determination.rate else {
                return currentTemp.duration > 0 ? currentTemp.rate : scheduledBasal
            }
            if (determination.duration ?? 0) == 0 { return scheduledBasal }
            return rate
        }

        var summary: String {
            "req \(determination.insulinReq.map { "\($0)" } ?? "nil") units \(units) " +
                "rate \(determination.rate.map { "\($0)" } ?? "nil") dur \(determination.duration.map { "\($0)" } ?? "nil") " +
                "effective \(effectiveRate)"
        }

        /// Insulin over the next 30 minutes if no further determination came (the pump reverts to scheduled
        /// basal when a temp ends), including the microbolus. Informational only.
        var insulinNext30Minutes: Decimal {
            var minutesAtRate: Decimal = 30
            var rate = effectiveRate
            if determination.rate == nil, currentTemp.duration > 0 {
                minutesAtRate = min(30, Decimal(currentTemp.duration))
                rate = currentTemp.rate
            } else if let duration = determination.duration, duration > 0 {
                minutesAtRate = min(30, duration)
            }
            return units + rate * minutesAtRate / 60 + scheduledBasal * (30 - minutesAtRate) / 60
        }
    }

    struct Pair {
        let testCase: Case
        let off: Outcome
        let on: Outcome
    }

    /// IOB and meal results by the inputs they are computed from. Neither generator reads the target, SMB
    /// or neutral-temp settings that differ between cases, so a cached result is exactly what a fresh run gives.
    final class Cache {
        var iob: [String: [IobResult]] = [:]
        var meal: [String: ComputedCarbs] = [:]
    }

    static func run(_ testCase: Case, cache: Cache? = nil) throws -> Pair {
        var preferences = Preferences()
        preferences.maxIOB = 8
        preferences.enableSMBAlways = testCase.smb
        preferences.enableUAM = testCase.smb
        preferences.smbDeliveryRatio = 0.5
        preferences.bolusIncrement = 0.05
        preferences.skipNeutralTemps = testCase.skipNeutralTemps

        let tempTargets: [TempTarget] = testCase.tempTarget.map { value in
            [TempTarget(
                name: "Test",
                createdAt: clock.addingTimeInterval(-10 * 60),
                targetTop: value,
                targetBottom: value,
                duration: 60,
                enteredBy: "Test",
                reason: "Test",
                isPreset: nil,
                enabled: true,
                halfBasalTarget: nil
            )]
        } ?? []
        let basalProfile = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: scheduledBasal)]
        var profile = try ProfileGenerator.generate(
            pumpSettings: PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 4),
            bgTargets: BGTargets(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                targets: [BGTargetEntry(low: target, high: target, start: "00:00:00", offset: 0)]
            ),
            basalProfile: basalProfile,
            isf: InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: [InsulinSensitivityEntry(sensitivity: isf, offset: 0, start: "00:00:00")]
            ),
            preferences: preferences,
            carbRatios: CarbRatios(units: .grams, schedule: [CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10)]),
            tempTargets: tempTargets,
            clock: clock
        )
        // Omnipod DASH table: 0.05 U/h steps, zero allowed
        profile.supportedBasalRates = PumpRateTables.flat

        var history: [PumpHistoryEvent] = []
        if testCase.bolus > 0 {
            history.append(ParityInputs.bolus(
                id: 1,
                at: clock.addingTimeInterval(TimeInterval(-testCase.bolusMinutesAgo * 60)),
                amount: testCase.bolus
            ))
        }
        for index in 0 ..< testCase.zeroTempHours * 2 {
            history += ParityInputs.tempBasalPair(
                id: 100 + index,
                at: clock.addingTimeInterval(TimeInterval(-(60 + index * 30) * 60)),
                rate: 0,
                duration: 30
            )
        }
        var currentTemp = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: clock)
        if let rate = testCase.runningTemp {
            let start = clock.addingTimeInterval(TimeInterval(-testCase.runningTempMinutesAgo * 60))
            history += ParityInputs.tempBasalPair(id: 999, at: start, rate: rate, duration: 30)
            currentTemp = TempBasal(duration: 30 - testCase.runningTempMinutesAgo, rate: rate, temp: .absolute, timestamp: start)
        }

        // 4 h of readings: flat, then a straight line over the last hour ending at `glucose`
        let values = (0 ..< 48).map { index in
            let stepsBeforeNow = 47 - index
            guard let lastDelta = testCase.lastDelta else {
                return max(40, min(400, testCase.glucose - testCase.delta * min(stepsBeforeNow, 12)))
            }
            if stepsBeforeNow == 0 { return testCase.glucose }
            return max(40, min(400, testCase.glucose - lastDelta - testCase.delta * min(stepsBeforeNow - 1, 11)))
        }
        let glucose = ParityInputs.trace(endingAt: clock, values: values)

        let historyKey = "\(testCase.bolus)|\(testCase.bolusMinutesAgo)|\(testCase.zeroTempHours)|" +
            "\(String(describing: testCase.runningTemp))|\(testCase.runningTempMinutesAgo)"
        let traceKey = values.map(String.init).joined(separator: ",")

        let autosens = Autosens(ratio: testCase.autosensRatio, newisf: nil)
        let iobKey = historyKey + "|\(testCase.autosensRatio)"
        let iob: [IobResult]
        if let cached = cache?.iob[iobKey] {
            iob = cached
        } else {
            iob = try IobGenerator.generate(history: history, profile: profile, clock: clock, autosens: autosens)
            cache?.iob[iobKey] = iob
        }
        let mealKey = historyKey + "|" + traceKey
        let meal: ComputedCarbs
        if let cached = cache?.meal[mealKey] {
            meal = cached
        } else {
            guard let generated = try MealGenerator.generate(
                pumpHistory: history,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbHistory: [],
                glucoseHistory: glucose
            ) else {
                throw ParityError("meal generation returned nil for \(testCase)")
            }
            meal = generated
            cache?.meal[mealKey] = generated
        }

        var orefVariables = ParityInputs.orefVariables(clock: clock)
        if let overrideTarget = testCase.overrideTarget {
            orefVariables = TrioCustomOrefVariables(
                average_total_data: 0,
                weightedAverage: 0,
                currentTDD: 0,
                past2hoursAverage: 0,
                date: clock,
                overridePercentage: testCase.overridePercentage,
                useOverride: true,
                duration: 120,
                unlimited: false,
                overrideTarget: overrideTarget,
                smbIsOff: false,
                advancedSettings: false,
                isfAndCr: true,
                isf: true,
                cr: true,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: 30,
                uamMinutes: 30
            )
        }

        func outcome(limit: Bool) throws -> Outcome {
            var runPreferences = preferences
            runPreferences.iobLimitsInsulinReq = limit
            guard let determination = try DeterminationGenerator.generate(
                profile: profile,
                preferences: runPreferences,
                currentTemp: currentTemp,
                iobData: iob,
                mealData: meal,
                autosensData: autosens,
                reservoirData: 100,
                glucose: glucose,
                microBolusAllowed: true,
                trioCustomOrefVariables: orefVariables,
                currentTime: clock
            ) else {
                throw ParityError("no determination for \(testCase)")
            }
            return Outcome(determination: determination, currentTemp: currentTemp, profile: profile, orefVariables: orefVariables)
        }

        let off = try outcome(limit: false)
        let on = try outcome(limit: true)
        return Pair(testCase: testCase, off: off, on: on)
    }

    /// The limit recomputed from the determination's own inputs: current glucose, IOB, the adjusted target the
    /// determination reports, and ISF adjusted for override and autosens. It mirrors DosingEngine's formula and
    /// rounding, so it checks plumbing only (that the generator hands the right naive, target and ISF to the
    /// limit), not the formula; the formula is pinned by the hand-worked literals in the other tests.
    static func expectedRoom(_ outcome: Outcome, clock: Date) -> Decimal? {
        let determination = outcome.determination
        guard let glucose = determination.bg, let iob = determination.iob, let target = determination.current_target,
              let ratio = determination.sensitivityRatio, let profileISF = outcome.profile.sens
        else { return nil }
        let sens = DeterminationGenerator.computeAdjustedSensitivity(
            sensitivity: profileISF,
            sensitivityRatio: ratio,
            trioCustomOrefVariables: outcome.orefVariables
        )
        let profileSens = outcome.profile.profileSensitivity(at: clock, trioCustomOrefVaribales: outcome.orefVariables)
        let naive = iob > 0 ? (glucose - iob * sens).jsRounded() : (glucose - iob * min(profileSens, sens)).jsRounded()
        return max(0, ((naive - target) / sens).rounded(scale: 2, roundingMode: .down))
    }

    struct Stats: CustomStringConvertible {
        var cases = 0
        var bound = 0
        var boundToZero = 0
        var unitsReduced = 0
        var rateLowered = 0
        var smbLowTempKeptLimitZero = 0
        var smbLowTempKeptLimitPositive = 0
        var stockSmbBelowIncrementToHighTempPath = 0
        var onKeepsRunningTempOffSetsNew = 0
        var onMoreInsulinOver30MinIfLoopStopped = 0

        var description: String {
            "cases \(cases), limit bound \(bound) (to 0: \(boundToZero)), units reduced \(unitsReduced), " +
                "effective rate lowered \(rateLowered), SMB low temp kept with limit 0: \(smbLowTempKeptLimitZero), " +
                "with limit > 0 and no microbolus: \(smbLowTempKeptLimitPositive), " +
                "stock SMB below increment then limit 0 (high temp path): \(stockSmbBelowIncrementToHighTempPath), " +
                "on keeps running temp while off sets a new one: \(onKeepsRunningTempOffSetsNew), " +
                "on more insulin over 30 min if the loop stopped: \(onMoreInsulinOver30MinIfLoopStopped)"
        }
    }

    /// Checks one pair and tallies what happened.
    ///
    /// Invariant: units(on) <= units(off) (nil = 0) and effectiveRate(on) <= effectiveRate(off).
    /// Also: insulinReq(on) == min(insulinReq(off), room recomputed independently); when it does not
    /// bind, on is identical to off; when it binds, the reason carries the marker.
    static func check(
        _ pair: Pair,
        clock: Date = IobLimitPipeline.clock,
        stats: inout Stats,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let off = pair.off.determination
        let on = pair.on.determination
        let label = pair.testCase.description
        stats.cases += 1

        #expect(pair.on.units <= pair.off.units, "\(label)", sourceLocation: sourceLocation)
        #expect(pair.on.effectiveRate <= pair.off.effectiveRate, "\(label)", sourceLocation: sourceLocation)
        #expect((on.rate == nil) == (on.duration == nil), "\(label)", sourceLocation: sourceLocation)

        if let offReq = off.insulinReq, let room = expectedRoom(pair.on, clock: clock) {
            #expect(on.insulinReq == min(offReq, room), "\(label)", sourceLocation: sourceLocation)
        } else {
            #expect(on.insulinReq == off.insulinReq, "\(label)", sourceLocation: sourceLocation)
        }

        guard let offReq = off.insulinReq, let onReq = on.insulinReq, onReq < offReq else {
            #expect(on.reason == off.reason, "\(label)", sourceLocation: sourceLocation)
            #expect(on.units == off.units, "\(label)", sourceLocation: sourceLocation)
            #expect(on.rate == off.rate, "\(label)", sourceLocation: sourceLocation)
            #expect(on.duration == off.duration, "\(label)", sourceLocation: sourceLocation)
            return
        }

        #expect(on.reason.contains("IOB limit \(offReq)→\(onReq), "), "\(label)", sourceLocation: sourceLocation)
        stats.bound += 1
        if onReq == 0 { stats.boundToZero += 1 }
        if pair.on.units < pair.off.units { stats.unitsReduced += 1 }
        if pair.on.effectiveRate < pair.off.effectiveRate { stats.rateLowered += 1 }

        let offSetSmbLowTemp = off.reason.contains("m low temp of")
        if offSetSmbLowTemp, pair.off.units > 0, pair.on.units == 0, on.rate == off.rate, on.duration == off.duration {
            if onReq == 0 { stats.smbLowTempKeptLimitZero += 1 } else { stats.smbLowTempKeptLimitPositive += 1 }
        }
        if onReq == 0, off.reason.contains(" insulinReq "), !offSetSmbLowTemp, pair.off.units == 0 {
            stats.stockSmbBelowIncrementToHighTempPath += 1
        }
        if on.rate == nil, pair.on.currentTemp.duration > 0, off.rate != nil {
            stats.onKeepsRunningTempOffSetsNew += 1
        }
        if pair.on.insulinNext30Minutes > pair.off.insulinNext30Minutes {
            stats.onMoreInsulinOver30MinIfLoopStopped += 1
        }
    }
}

@Suite("IOB limit: whole pipeline") struct IobLimitPipelineTests {
    private typealias Case = IobLimitPipeline.Case

    private func run(_ testCase: Case) throws -> IobLimitPipeline.Pair {
        let pair = try IobLimitPipeline.run(testCase)
        var stats = IobLimitPipeline.Stats()
        IobLimitPipeline.check(pair, stats: &stats)
        print("IOB limit case \(testCase): off \(pair.off.summary) | on \(pair.on.summary)")
        print("IOB limit case on reason: \(pair.on.determination.reason)")
        return pair
    }

    @Test(
        "Limit to 0 while a high temp runs: the next determination brings the temp back to basal (SMB off)"
    ) func limitToZeroBringsHighTempBackToBasal() throws {
        // IOB 3.59 x ISF 25 already takes 160 to naive 70, below target 90
        let pair = try run(Case(glucose: 160, delta: 6, bolus: 4, bolusMinutesAgo: 45, runningTemp: 2.5, smb: false))
        #expect(pair.off.determination.insulinReq == dec("0.64"))
        // stock leaves the 2.5 U/h temp running ("temp 2.5 >~ req")
        #expect(pair.off.determination.rate == nil)
        #expect(pair.off.effectiveRate == 2.5)
        #expect(pair.on.determination.insulinReq == 0)
        #expect(pair.on.determination.rate == IobLimitPipeline.scheduledBasal)
        #expect(pair.on.determination.duration == 30)
        #expect(pair.on.effectiveRate == IobLimitPipeline.scheduledBasal)
        #expect(pair.on.determination.reason.contains("> 2 * insulinReq. Setting temp basal of 1U/hr"))
    }

    @Test(
        "Limit to 0 with SMB on where stock pairs a microbolus with an SMB low temp: no microbolus, same low temp"
    ) func limitToZeroWithHighTempAndSmb() throws {
        let pair = try run(Case(glucose: 160, delta: 6, bolus: 4, bolusMinutesAgo: 45, runningTemp: 2.5, smb: true))
        // stock: 0.5 U microbolus plus a 30-minute low temp that replaces the running 2.5 U/h
        #expect(pair.off.determination.insulinReq == dec("2.96"))
        #expect(pair.off.determination.units == 0.5)
        #expect(pair.off.determination.rate == dec("0.17"))
        #expect(pair.off.determination.duration == 30)
        #expect(pair.on.determination.insulinReq == 0)
        #expect(pair.on.determination.units == nil)
        #expect(pair.on.determination.rate == pair.off.determination.rate)
        #expect(pair.on.determination.duration == pair.off.determination.duration)
    }

    @Test(
        "Limit to 0 with a high temp within 25% of basal and over 20 min left: stock's close-enough rule keeps it"
    ) func limitToZeroNearBasalHighTempBand() throws {
        // setTempBasal treats a running temp within 80-120% of the request as close enough while more than
        // 20 minutes remain, so basal 1.0 against a running 1.15 leaves the 1.15 on for its last 25 minutes
        let kept = try run(Case(glucose: 160, delta: 6, bolus: 4, bolusMinutesAgo: 45, runningTemp: 1.15, smb: false))
        #expect(kept.on.determination.insulinReq == 0)
        #expect(kept.on.determination.rate == nil)
        #expect(kept.on.effectiveRate == 1.15)
        #expect(kept.on.determination.reason.contains("~ req 1U/hr: no temp required"))

        // with 20 minutes or less left it is replaced by basal
        let replaced = try run(Case(
            glucose: 160,
            delta: 6,
            bolus: 4,
            bolusMinutesAgo: 45,
            runningTemp: 1.15,
            runningTempMinutesAgo: 10,
            smb: false
        ))
        #expect(replaced.on.determination.insulinReq == 0)
        #expect(replaced.on.determination.rate == IobLimitPipeline.scheduledBasal)
        #expect(replaced.on.determination.duration == 30)
    }

    @Test(
        "Limit to 0 with SMB on where stock pairs a microbolus with a high temp: no microbolus, temp at basal"
    ) func limitToZeroWithSmb() throws {
        // close to worked example 167 / 3.74: IOB 3.7 takes 167 to naive 75
        let pair = try run(Case(glucose: 167, delta: 5, bolus: 4.3, bolusMinutesAgo: 45, smb: true))
        #expect(pair.off.determination.insulinReq == dec("2.84"))
        #expect(pair.off.determination.units == 0.5)
        #expect(pair.off.determination.rate == 3)
        #expect(!pair.off.determination.reason.contains("m low temp of"))
        #expect(pair.on.determination.insulinReq == 0)
        #expect(pair.on.determination.units == nil)
        #expect(pair.on.determination.rate == IobLimitPipeline.scheduledBasal)
        #expect(pair.on.determination.duration == 30)
    }

    @Test(
        "Negative IOB with autosens 0.8: naive uses min(profile ISF, adjusted ISF), the limit still applies"
    ) func negativeIob() throws {
        let pair = try run(Case(glucose: 140, delta: 12, zeroTempHours: 2, smb: false, autosensRatio: 0.8))
        #expect((pair.on.determination.iob ?? 0) < 0)
        // IOB -0.968, ISF 25 / 0.8 = 31.3: naive 140 + 0.968 x min(25, 31.3) = 164, room (164 - 90) / 31.3 = 2.36
        // (with 31.3 in naive it would have been 2.55)
        #expect(pair.off.determination.insulinReq == dec("3.58"))
        #expect(pair.on.determination.insulinReq == dec("2.36"))
    }

    @Test("Active temp target: the limit uses the temp target") func tempTarget() throws {
        let pair = try run(Case(glucose: 190, delta: 6, bolus: 3, bolusMinutesAgo: 45, smb: false, tempTarget: 120))
        #expect(pair.on.determination.current_target == 120)
        // naive 190 - 2.579 x 25 = 126, room (126 - 120) / 25 = 0.24; stock's 1.64 is from the forecast
        #expect(pair.off.determination.insulinReq == dec("1.64"))
        #expect(pair.on.determination.insulinReq == dec("0.24"))
    }

    @Test("Override target and percentage: the limit uses the override target and ISF") func overrideTarget() throws {
        let pair = try run(Case(
            glucose: 190,
            delta: 6,
            bolus: 3,
            bolusMinutesAgo: 45,
            smb: true,
            overrideTarget: 110,
            overridePercentage: 120
        ))
        #expect(pair.on.determination.current_target == 110)
        // ISF 25 / 1.2 = 20.8, naive 190 - 2.579 x 20.8 = 136, room (136 - 110) / 20.8 = 1.25
        #expect(pair.off.determination.insulinReq == dec("5.34"))
        #expect(pair.on.determination.insulinReq == dec("1.25"))
    }

    // 1.2: ISF 20.8, naive 190 - 2.579 x 20.8 = 136, room 46 / 20.8 = 2.21 (stock 5.421 is max_iob 8 - IOB 2.579)
    // 0.8: ISF 31.3, naive 190 - 2.579 x 31.3 = 109, room 19 / 31.3 = 0.6 (stock 3.67 is from the forecast)
    @Test(
        "Autosens ratio 1.2 and 0.8: the limit uses the adjusted ISF",
        arguments: [("1.2", "5.421", "2.21"), ("0.8", "3.67", "0.6")]
    ) func autosensRatio(ratio: String, stock: String, limited: String) throws {
        let pair = try run(Case(glucose: 190, delta: 6, bolus: 3, bolusMinutesAgo: 45, smb: true, autosensRatio: dec(ratio)))
        #expect(pair.on.determination.sensitivityRatio == dec(ratio))
        #expect(pair.off.determination.insulinReq == dec(stock))
        #expect(pair.on.determination.insulinReq == dec(limited))
    }

    @Test("SMB off: the high temp rate is basal + 2 x the limited insulinReq") func smbDisabledHighTemp() throws {
        let pair = try run(Case(glucose: 175, delta: 6, bolus: 3, bolusMinutesAgo: 45, smb: false))
        // naive 175 - 2.579 x 25 = 110.5, rounded 111 as stock does; room (111 - 90) / 25 = 0.84
        #expect(pair.off.determination.insulinReq == dec("2.24"))
        #expect(pair.on.determination.insulinReq == dec("0.84"))
        // off: 1 + 2 x 2.24 = 5.48, capped at max safe basal 3 (3 x max daily basal 1)
        #expect(pair.off.determination.rate == 3)
        // on: 1 + 2 x 0.84 = 2.68, floored to the 0.05 rate table
        #expect(pair.on.determination.rate == dec("2.65"))
        #expect(pair.on.determination.duration == 30)
        #expect(pair.on.units == 0)
    }

    @Test(
        "Marker follows the stock text, has no \"; \", leaves the tag cloud alone; shown on home unless a \"; \" follows"
    ) func markerInProducedReasons() throws {
        let glucoseLabels = [
            "ISF:", "Target:", "Dev:", "BGI:", "minPredBG", "minGuardBG", "IOBpredBG", "COBpredBG", "UAMpredBG", "Eventual BG",
            "% of BG", "<", ">"
        ]
        let cases: [(testCase: Case, marker: String, after: String, inConclusion: Bool)] = [
            // SMB off: the high temp path appends no "; ", so the home screen conclusion shows the marker
            (
                Case(glucose: 160, delta: 6, bolus: 4, bolusMinutesAgo: 45, runningTemp: 2.5, smb: false),
                "IOB limit 0.64→0, ", "Eventual BG 121 >= 90, ", true
            ),
            // SMB on: the SMB path appends "; setting 30m low temp of 0.17U/h"
            (
                Case(glucose: 160, delta: 6, bolus: 4, bolusMinutesAgo: 45, runningTemp: 2.5, smb: true),
                "IOB limit 2.96→0, ", "Eventual BG 223 >= 90, ", false
            ),
            // SMB on after max_iob: the SMB path appends "; maxBolus 0.5"
            (
                Case(glucose: 190, delta: 6, bolus: 3, bolusMinutesAgo: 45, smb: true, autosensRatio: dec("1.2")),
                "IOB limit 5.421→2.21, ", "max_iob 8, ", false
            )
        ]
        for item in cases {
            let pair = try run(item.testCase)
            let on = pair.on.determination
            let off = pair.off.determination
            let start = try #require(on.reason.range(of: "IOB limit "), "\(item.testCase)")
            let end = try #require(on.reason.range(of: ", ", range: start.upperBound ..< on.reason.endIndex), "\(item.testCase)")
            let marker = String(on.reason[start.lowerBound ..< end.upperBound])
            let beforeMarker = String(on.reason[..<start.lowerBound])

            #expect(marker == item.marker)
            #expect(!marker.contains("; "))
            #expect(on.reason.components(separatedBy: "IOB limit ").count == 2)
            for label in glucoseLabels {
                #expect(!marker.contains(label), "\(label)")
            }
            // inserted right where stock's own text continues, after the "; " that ends the tag cloud
            #expect(beforeMarker.hasSuffix(item.after))
            #expect(off.reason.hasPrefix(beforeMarker))
            #expect(beforeMarker.contains("; "))
            #expect(on.reasonParts == off.reasonParts)
            #expect(on.reasonConclusion.contains(marker) == item.inConclusion)
        }
    }
}

@Suite("IOB limit: on never gives more than off") struct IobLimitInvariantTests {
    private typealias Case = IobLimitPipeline.Case

    /// What this sweep adds over the randomized tests below: real ProfileGenerator, IobGenerator, MealGenerator
    /// and glucose-status output feeding the generator, and the plumbing check in `IobLimitPipeline.check`.
    /// The randomized tests carry the breadth (COB, dynamic ISF, short temps, skip-neutral cancels, waiting SMBs).
    @Test(
        "Sweep through the whole pipeline: units and effective rate on <= off",
        arguments: ["glucose 130", "glucose 190", "turning traces"]
    ) func sweep(part: String) throws {
        var stats = IobLimitPipeline.Stats()
        let cache = IobLimitPipeline.Cache()
        let started = Date()
        for testCase in Self.sweepCases(part) {
            let pair = try IobLimitPipeline.run(testCase, cache: cache)
            IobLimitPipeline.check(pair, stats: &stats)
        }
        print("IOB limit sweep \(part): \(stats) in \(Int(Date().timeIntervalSince(started)))s")
        #expect(stats.bound * 10 > stats.cases, "\(stats)")
        #expect(stats.boundToZero > 0, "\(stats)")
        #expect(stats.unitsReduced + stats.rateLowered > 0, "\(stats)")
    }

    private static func sweepCases(_ part: String) -> [Case] {
        var cases: [Case] = []
        if part == "turning traces" {
            // rose, then turned down at the last reading: the IOB forecast falls below naive while the averaged
            // deviation still lifts eventual glucose, the shape that pairs a limited microbolus with an SMB low temp
            for glucose in stride(from: 120, through: 200, by: 4) {
                for bolus: (units: Decimal, minutesAgo: Int) in [(4, 45), (2, 60)] {
                    for lastDelta in [-5, -10] {
                        cases.append(Case(
                            glucose: glucose,
                            delta: 8,
                            lastDelta: lastDelta,
                            bolus: bolus.units,
                            bolusMinutesAgo: bolus.minutesAgo,
                            smb: true
                        ))
                    }
                }
            }
            return cases
        }

        let glucose = part == "glucose 130" ? 130 : 190
        // bolus or zero temps for IOB of about 0, 1.8, 4.5 and -1 U
        let iobSetups: [(bolus: Decimal, minutesAgo: Int, zeroTempHours: Int)] = [(0, 60, 0), (2, 60, 0), (5, 45, 0), (0, 60, 2)]
        // none, high, within the close-enough band of basal (low temps are in the randomized tests)
        let runningTemps: [(rate: Decimal?, minutesAgo: Int)] = [(nil, 0), (2.5, 5), (1.1, 5)]
        let variants: [(tempTarget: Decimal?, overrideTarget: Decimal?, autosensRatio: Decimal)] = [
            (nil, nil, 1), (120, nil, 1), (nil, 110, 1.2)
        ]
        for delta in [-3, 6] {
            for iobSetup in iobSetups {
                for runningTemp in runningTemps {
                    for smb in [true, false] {
                        for variant in variants {
                            cases.append(Case(
                                glucose: glucose,
                                delta: delta,
                                bolus: iobSetup.bolus,
                                bolusMinutesAgo: iobSetup.minutesAgo,
                                zeroTempHours: iobSetup.zeroTempHours,
                                runningTemp: runningTemp.rate,
                                runningTempMinutesAgo: runningTemp.minutesAgo,
                                smb: smb,
                                tempTarget: variant.tempTarget,
                                overrideTarget: variant.overrideTarget,
                                overridePercentage: variant.overrideTarget == nil ? 100 : 120,
                                autosensRatio: variant.autosensRatio
                            ))
                        }
                    }
                }
            }
        }
        return cases
    }

    @Test("Every parity scenario, off vs on") func parityScenarios() throws {
        var stats = IobLimitPipeline.Stats()
        for name in ParityScenarios.allNames {
            let scenario = ParityScenarios.build(name)
            var onPreferences = scenario.preferences
            onPreferences.iobLimitsInsulinReq = true
            let onScenario = ParityScenario(
                name: scenario.name,
                clock: scenario.clock,
                glucose: scenario.glucose,
                pumpHistory: scenario.pumpHistory,
                carbs: scenario.carbs,
                tempTargets: scenario.tempTargets,
                preferences: onPreferences,
                orefVariables: scenario.orefVariables,
                currentTemp: scenario.currentTemp,
                reservoir: scenario.reservoir,
                pumpSettings: scenario.pumpSettings,
                bgTargets: scenario.bgTargets,
                basalProfile: scenario.basalProfile,
                isf: scenario.isf,
                carbRatios: scenario.carbRatios
            )
            let off = try ParityScenarios.runPipeline(scenario)
            let on = try ParityScenarios.runPipeline(onScenario)
            let offDetermination = try #require(off.determination, "\(name)")
            let onDetermination = try #require(on.determination, "\(name)")
            var testCase = IobLimitPipeline.Case()
            testCase.name = "parity scenario \(name)"
            let pair = IobLimitPipeline.Pair(
                testCase: testCase,
                off: IobLimitPipeline.Outcome(
                    determination: offDetermination,
                    currentTemp: scenario.currentTemp,
                    profile: off.profile,
                    orefVariables: scenario.orefVariables
                ),
                on: IobLimitPipeline.Outcome(
                    determination: onDetermination,
                    currentTemp: scenario.currentTemp,
                    profile: on.profile,
                    orefVariables: scenario.orefVariables
                )
            )
            print("IOB limit parity \(name): off \(pair.off.summary) | on \(pair.on.summary)")
            IobLimitPipeline.check(pair, clock: scenario.clock, stats: &stats)
        }
        print("IOB limit parity scenarios: \(stats)")
    }
}

// MARK: - IOB limit: fixed-seed randomized tests (built on the review probe)

/// SplitMix64. A fixed seed gives the same cases on every run and machine.
struct IobLimitRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func chance(_ percent: Int) -> Bool {
        int(0 ... 99) < percent
    }

    mutating func decimal(_ range: ClosedRange<Int>, _ divisor: Int) -> Decimal {
        Decimal(int(range)) / Decimal(divisor)
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[int(0 ... values.count - 1)]
    }
}

/// Rate on the pump right after enactment: no new temp keeps the running temp (or scheduled basal when none
/// runs); a 0-minute temp cancels to scheduled basal.
private func effectiveRate(_ determination: Determination, running: TempBasal, scheduled: Decimal) -> Decimal {
    guard let rate = determination.rate else {
        return running.duration > 0 ? running.rate : scheduled
    }
    return (determination.duration ?? 0) == 0 ? scheduled : rate
}

/// Everything `determineSMBDelivery` and `determineHighTempBasal` read, drawn at random.
private struct IobLimitTailInputs: CustomStringConvertible {
    var profile: Profile
    var orefVariables: TrioCustomOrefVariables
    var meal: ComputedCarbs
    var iobData: [IobResult]
    var now: Date
    var microBolusAllowed: Bool
    var smbIsEnabled: Bool
    var currentGlucose: Decimal
    var threshold: Decimal
    var target: Decimal
    var naive: Decimal
    var minIOBPred: Decimal
    var sens: Decimal
    var carbRatio: Decimal
    var basal: Decimal
    var currentTemp: TempBasal
    var minPred: Decimal
    var eventual: Decimal
    var maxIob: Decimal
    var iob: Decimal

    var description: String {
        "scheduled \(profile.currentBasal ?? 0) basal \(basal) temp \(currentTemp.rate)@\(currentTemp.duration)m " +
            "skipNeutral \(profile.skipNeutralTemps) smb \(microBolusAllowed && smbIsEnabled) bg \(currentGlucose) " +
            "threshold \(threshold) increment \(profile.bolusIncrement) ratio \(profile.smbDeliveryRatio) iob \(iob) " +
            "naive \(naive) minIOBPred \(minIOBPred) target \(target) sens \(sens) cob \(meal.mealCOB) " +
            "rates \(profile.supportedBasalRates.count) maxBasal \(profile.maxBasal ?? 0)"
    }

    static func random(_ rng: inout IobLimitRandom, now: Date) -> IobLimitTailInputs {
        var profile = Profile()
        let scheduled = rng.decimal(2 ... 600, 200)
        profile.currentBasal = scheduled
        profile.maxDailyBasal = scheduled * rng.decimal(100 ... 250, 100)
        profile.maxBasal = rng.chance(50) ? scheduled * rng.decimal(100 ... 800, 100) : rng.decimal(5 ... 100, 10)
        profile.maxDailySafetyMultiplier = rng.pick([3, 4, 2, 1])
        profile.currentBasalSafetyMultiplier = rng.pick([4, 5, 3, 1])
        profile.supportedBasalRates = rng.pick([
            [], PumpRateTables.flat, PumpRateTables.omnipodEros, PumpRateTables.dana, PumpRateTables.minimedGen23
        ])
        profile.smbDeliveryRatio = rng.decimal(5 ... 150, 100)
        profile.bolusIncrement = rng.pick([dec("0.01"), dec("0.025"), dec("0.05"), dec("0.1")])
        profile.maxSMBBasalMinutes = Decimal(rng.pick([15, 30, 45, 60, 90, 120]))
        profile.maxUAMSMBBasalMinutes = Decimal(rng.pick([15, 30, 45, 60, 90, 120]))
        profile.smbInterval = Decimal(rng.pick([1, 3, 5, 10]))
        profile.skipNeutralTemps = rng.chance(40)

        let useOverride = rng.chance(30)
        let orefVariables = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: now,
            overridePercentage: Decimal(rng.int(5 ... 20) * 10),
            useOverride: useOverride,
            duration: 60,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: rng.chance(50),
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: Decimal(rng.pick([0, 15, 30, 60, 90])),
            uamMinutes: Decimal(rng.pick([0, 15, 30, 60, 90]))
        )

        let cob: Decimal = rng.chance(60) ? 0 : rng.decimal(1 ... 120, 1)
        let meal = ComputedCarbs(
            carbs: cob > 0 ? cob + rng.decimal(0 ... 60, 1) : 0,
            mealCOB: cob,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [],
            lastCarbTime: 0
        )

        let iob = rng.decimal(-300 ... 1000, 100)
        // 0 to 30 minutes ago, so the SMB interval sometimes makes it wait
        let lastBolusTime: UInt64? = rng.chance(15) ? nil :
            UInt64((now.timeIntervalSince1970 - Double(rng.int(0 ... 1800))) * 1000)
        let zeroTemp = IobResult.IobWithZeroTemp(
            iob: iob,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now
        )
        let iobData = [IobResult(
            iob: iob,
            activity: 0,
            basaliob: 0,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now,
            iobWithZeroTemp: zeroTemp,
            lastBolusTime: lastBolusTime,
            lastTemp: nil
        )]

        let ratio: Decimal = rng.chance(50) ? 1 : rng.decimal(50 ... 200, 100)
        let basal = rng.chance(15) ? scheduled : scheduled * orefVariables.overrideFactor() * ratio

        let target = rng.decimal(70 ... 180, 1)
        let naive = target + rng.decimal(-150 ... 200, 1)

        // minutes left on the running temp: none, 1-5, 6-20, 21-30, 31-120, exactly 30
        let duration: Int
        switch rng.int(0 ... 5) {
        case 0: duration = 0
        case 1: duration = rng.int(1 ... 5)
        case 2: duration = rng.int(6 ... 20)
        case 3: duration = rng.int(21 ... 30)
        case 4: duration = rng.int(31 ... 120)
        default: duration = 30
        }
        let maxSafe = min(
            profile.maxBasal ?? 0,
            profile.maxDailySafetyMultiplier * (profile.maxDailyBasal ?? 0),
            profile.currentBasalSafetyMultiplier * scheduled
        )
        let rate: Decimal
        switch rng.int(0 ... 6) {
        case 0: rate = 0
        case 1: rate = (basal * rng.decimal(0 ... 80, 100)).rounded(scale: 3)
        case 2: rate = (basal * rng.decimal(80 ... 125, 100)).rounded(scale: 3)
        case 3: rate = basal
        case 4: rate = scheduled
        case 5: rate = (basal * rng.decimal(125 ... 300, 100)).rounded(scale: 3)
        default: rate = (maxSafe * rng.decimal(0 ... 130, 100)).rounded(scale: 2)
        }

        return IobLimitTailInputs(
            profile: profile,
            orefVariables: orefVariables,
            meal: meal,
            iobData: iobData,
            now: now,
            microBolusAllowed: rng.chance(90),
            smbIsEnabled: rng.chance(75),
            currentGlucose: rng.decimal(39 ... 400, 1),
            threshold: rng.decimal(60 ... 120, 1),
            target: target,
            naive: naive,
            minIOBPred: naive + rng.decimal(-80 ... 80, 1),
            sens: rng.decimal(50 ... 2000, 10),
            carbRatio: rng.decimal(30 ... 250, 10),
            basal: basal,
            currentTemp: TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: now),
            minPred: rng.decimal(30 ... 400, 1),
            eventual: rng.decimal(30 ... 400, 1),
            maxIob: rng.decimal(0 ... 150, 10),
            iob: iob
        )
    }

    /// The generator's tail: SMB delivery, then, unless it set its low temp, the high temp path
    /// (which enacts through setTempBasal).
    func tail(insulinRequired: Decimal, stock: Decimal?) throws -> (viaSmb: Bool, determination: Determination) {
        let smb = try DosingEngine.determineSMBDelivery(
            insulinRequired: insulinRequired,
            stockInsulinRequired: stock,
            microBolusAllowed: microBolusAllowed,
            smbIsEnabled: smbIsEnabled,
            currentGlucose: currentGlucose,
            threshold: threshold,
            profile: profile,
            trioCustomOrefVariables: orefVariables,
            mealData: meal,
            iobData: iobData,
            currentTime: now,
            targetGlucose: target,
            naiveEventualGlucose: naive,
            minIOBForecastedGlucose: minIOBPred,
            adjustedSensitivity: sens,
            adjustedCarbRatio: carbRatio,
            basal: basal,
            determination: blankDetermination(reason: "Autosens ratio: 1, ISF: 50→50; ")
        )
        if smb.shouldSetTempBasal { return (true, smb.determination) }
        let highTemp = try DosingEngine.determineHighTempBasal(
            insulinRequired: insulinRequired,
            basal: basal,
            profile: profile,
            currentTemp: currentTemp,
            determination: smb.determination
        )
        return (false, highTemp)
    }
}

private func sameOutput(_ lhs: Determination, _ rhs: Determination) -> Bool {
    lhs.reason == rhs.reason && lhs.units == rhs.units && lhs.rate == rhs.rate && lhs.duration == rhs.duration &&
        lhs.insulinReq == rhs.insulinReq
}

@Suite("IOB limit: randomized SMB and temp basal tail") struct IobLimitTailRandomizedTests {
    /// Each seed runs in parallel; together they take a few seconds.
    @Test(
        "Fixed-seed random inputs through determineSMBDelivery, determineHighTempBasal and setTempBasal: on <= off",
        arguments: [UInt64(0x5EED_1234_ABCD_0001), 0x5EED_1234_ABCD_0002, 0x5EED_1234_ABCD_0003, 0x5EED_1234_ABCD_0004]
    ) func randomized(seed: UInt64) throws {
        var rng = IobLimitRandom(seed: seed)
        let now = Date(timeIntervalSince1970: 1_781_000_000)
        let cases = 1500
        let started = Date()

        var boundToZero = 0, boundPartly = 0, notBound = 0
        var lowTempKeptByStockValue = 0, boundWithCob = 0, boundWithShortTemp = 0, boundWhileWaiting = 0
        var cancels = 0, unitsReduced = 0, rateLowered = 0
        var unitsViolations = 0, rateViolations = 0, offChanged = 0, notBindingChanged = 0, ruleViolations = 0
        var examples: [String] = []
        func note(_ text: String) {
            if examples.count < 20 { examples.append(text) }
        }

        for index in 0 ..< cases {
            let inputs = IobLimitTailInputs.random(&rng, now: now)
            let scheduled = inputs.profile.currentBasal ?? 0

            var stock: Decimal
            var limited: Decimal
            if rng.chance(50) {
                // through calculateInsulinRequired, checked against the rule worked out with exact arithmetic
                let base = blankDetermination(reason: "Autosens ratio: 1; ")
                let (stockValue, stockDetermination) = DosingEngine.calculateInsulinRequired(
                    minForecastGlucose: inputs.minPred,
                    eventualGlucose: inputs.eventual,
                    targetGlucose: inputs.target,
                    adjustedSensitivity: inputs.sens,
                    maxIob: inputs.maxIob,
                    currentIob: inputs.iob,
                    determination: base
                )
                var results: [Bool: DosingEngine.InsulinRequirement] = [:]
                for limit in [false, true] {
                    results[limit] = DosingEngine.calculateInsulinRequired(
                        minForecastGlucose: inputs.minPred,
                        eventualGlucose: inputs.eventual,
                        targetGlucose: inputs.target,
                        adjustedSensitivity: inputs.sens,
                        maxIob: inputs.maxIob,
                        currentIob: inputs.iob,
                        naiveEventualGlucose: inputs.naive,
                        iobLimitsInsulinReq: limit,
                        determination: base
                    )
                }
                let off = results[false]!
                let on = results[true]!
                stock = on.stockInsulinRequired
                limited = on.insulinRequired
                let ruleValue = min(stockValue, max(0, (inputs.naive - inputs.target) / inputs.sens))
                let ruleBroken = stock != stockValue || off.insulinRequired != stockValue ||
                    !sameOutput(off.determination, stockDetermination) ||
                    limited > ruleValue || ruleValue - limited >= dec("0.01") ||
                    (limited == stockValue && !sameOutput(on.determination, stockDetermination)) ||
                    (limited < stockValue && (
                        on.determination.insulinReq != limited ||
                            on.determination.reason != stockDetermination.reason + "IOB limit \(stockValue)→\(limited), "
                    ))
                if ruleBroken {
                    ruleViolations += 1
                    note("RULE #\(index) stock \(stockValue) limited \(limited) rule \(ruleValue) \(inputs)")
                }
            } else {
                // any stock value, limited to 0, partly, not at all, or just below one microbolus
                stock = rng.decimal(-100 ... 600, 100)
                if stock <= 0 {
                    limited = stock
                } else {
                    switch rng.int(0 ... 3) {
                    case 0: limited = 0
                    case 1: limited = (stock * rng.decimal(1 ... 99, 100)).rounded(scale: 2, roundingMode: .down)
                    case 2: limited = stock
                    default:
                        let ratio = min(inputs.profile.smbDeliveryRatio, 1)
                        limited = min(
                            stock,
                            (inputs.profile.bolusIncrement / ratio * rng.decimal(1 ... 99, 100))
                                .rounded(scale: 3, roundingMode: .down)
                        )
                    }
                }
            }
            if stock > 0, rng.chance(10) {
                limited = 0
            }

            let off = try inputs.tail(insulinRequired: stock, stock: stock)
            let stockPath = try inputs.tail(insulinRequired: stock, stock: nil)
            let on = try inputs.tail(insulinRequired: limited, stock: stock)
            let label = "#\(index) stock \(stock) limited \(limited) \(inputs)"

            if !sameOutput(off.determination, stockPath.determination) || off.viaSmb != stockPath.viaSmb {
                offChanged += 1
                note("OFF CHANGED " + label)
            }
            if limited == stock, !sameOutput(on.determination, off.determination) || on.viaSmb != off.viaSmb {
                notBindingChanged += 1
                note("NOT BINDING BUT DIFFERENT " + label)
            }

            let unitsOn = on.determination.units ?? 0
            let unitsOff = off.determination.units ?? 0
            let rateOn = effectiveRate(on.determination, running: inputs.currentTemp, scheduled: scheduled)
            let rateOff = effectiveRate(off.determination, running: inputs.currentTemp, scheduled: scheduled)
            if unitsOn > unitsOff {
                unitsViolations += 1
                note("UNITS \(unitsOn) > \(unitsOff) " + label)
            }
            if rateOn > rateOff {
                rateViolations += 1
                note("RATE \(rateOn) > \(rateOff) " + label)
            }
            if on.determination.duration == 0 || off.determination.duration == 0 { cancels += 1 }

            guard limited < stock else {
                notBound += 1
                continue
            }
            if limited == 0 { boundToZero += 1 } else { boundPartly += 1 }
            if unitsOn < unitsOff { unitsReduced += 1 }
            if rateOn < rateOff { rateLowered += 1 }
            if inputs.meal.mealCOB > 0 { boundWithCob += 1 }
            if inputs.currentTemp.duration > 0, inputs.currentTemp.duration < 21 { boundWithShortTemp += 1 }
            if on.determination.reason.contains("Waiting") { boundWhileWaiting += 1 }
            // the corner the stock value exists for: deciding on the limited value alone would drop the SMB low temp
            let decidedOnLimited = try inputs.tail(insulinRequired: limited, stock: nil)
            if on.viaSmb, !decidedOnLimited.viaSmb { lowTempKeptByStockValue += 1 }
        }

        let summary = "seed \(String(seed, radix: 16)): \(cases) cases, bound to 0 \(boundToZero), partly \(boundPartly), " +
            "not \(notBound); units reduced \(unitsReduced), effective rate lowered \(rateLowered); low temp kept by the " +
            "stock value \(lowTempKeptByStockValue); bound with COB \(boundWithCob), with a running temp of 1-20 min " +
            "\(boundWithShortTemp), while waiting to microbolus \(boundWhileWaiting); cancels \(cancels); violations: " +
            "units \(unitsViolations), rate \(rateViolations), off changed \(offChanged), not binding but different " +
            "\(notBindingChanged), rule \(ruleViolations); \(Int(Date().timeIntervalSince(started) * 1000)) ms"
        print("IOB limit tail randomized: " + summary)
        for example in examples {
            print("IOB limit tail randomized example: " + example)
        }
        #expect(unitsViolations == 0, "\(summary) \(examples)")
        #expect(rateViolations == 0, "\(summary) \(examples)")
        #expect(offChanged == 0, "\(summary) \(examples)")
        #expect(notBindingChanged == 0, "\(summary) \(examples)")
        #expect(ruleViolations == 0, "\(summary) \(examples)")
        // never vacuous: the limit must bind often, in every way that matters
        #expect(boundToZero * 10 >= cases, "\(summary)")
        #expect(boundPartly * 10 >= cases, "\(summary)")
        #expect(unitsReduced * 20 >= cases, "\(summary)")
        #expect(rateLowered * 20 >= cases, "\(summary)")
        #expect(lowTempKeptByStockValue * 100 >= cases, "\(summary)")
        #expect(boundWithCob * 20 >= cases, "\(summary)")
        #expect(boundWithShortTemp * 20 >= cases, "\(summary)")
        #expect(boundWhileWaiting * 100 >= cases, "\(summary)")
        #expect(cancels * 100 >= cases, "\(summary)")
    }
}

@Suite("IOB limit: randomized single determinations") struct IobLimitGeneratorRandomizedTests {
    /// Random single-cycle inputs through DeterminationGenerator.determineBasal, off and on: COB, UAM, dynamic ISF,
    /// temp targets, overrides, autosens, skip-neutral temps, short running temps, SMB interval waits.
    /// Each seed runs in parallel.
    @Test(
        "Fixed-seed random determinations: on <= off, identical JSON when the limit does not bind",
        arguments: [UInt64(0xC0FF_EE00_0000_0042), 0xC0FF_EE00_0000_0043, 0xC0FF_EE00_0000_0044, 0xC0FF_EE00_0000_0045]
    ) func randomized(seed: UInt64) throws {
        var rng = IobLimitRandom(seed: seed)
        let cases = 120
        let started = Date()
        var stats = IobLimitPipeline.Stats()
        var threw = 0, dynamicBound = 0, cobBound = 0, jsonDifferences = 0

        for index in 0 ..< cases {
            let now = Date(timeIntervalSince1970: 1_781_000_000 + Double(rng.int(0 ... 59) * 60))
            var profile = Profile()
            let scheduled = rng.decimal(4 ... 500, 200)
            profile.currentBasal = scheduled
            profile.maxDailyBasal = scheduled * rng.decimal(100 ... 200, 100)
            profile.maxBasal = rng.decimal(5 ... 80, 10)
            let target = rng.decimal(80 ... 150, 1)
            profile.minBg = target
            profile.maxBg = target + rng.decimal(0 ... 60, 1)
            profile.targetBg = target
            if rng.chance(15) {
                let tempTarget = rng.decimal(80 ... 160, 1)
                profile.minBg = tempTarget
                profile.maxBg = tempTarget
                profile.targetBg = tempTarget
                profile.temptargetSet = true
            }
            profile.sens = rng.decimal(150 ... 1500, 10)
            profile.carbRatio = rng.decimal(40 ... 200, 10)
            profile.thresholdSetting = rng.decimal(60 ... 90, 1)
            profile.maxIob = rng.decimal(0 ... 120, 10)
            profile.enableSMBAlways = rng.chance(60)
            profile.enableSMBWithCOB = rng.chance(30)
            profile.enableUAM = rng.chance(60)
            profile.allowSMBWithHighTemptarget = rng.chance(30)
            profile.bolusIncrement = rng.pick([dec("0.01"), dec("0.025"), dec("0.05"), dec("0.1")])
            profile.smbDeliveryRatio = rng.decimal(30 ... 100, 100)
            profile.maxSMBBasalMinutes = Decimal(rng.pick([30, 60, 90, 120]))
            profile.maxUAMSMBBasalMinutes = Decimal(rng.pick([30, 60, 90, 120]))
            profile.skipNeutralTemps = rng.chance(30)
            profile.supportedBasalRates = rng.pick([[], PumpRateTables.flat, PumpRateTables.minimedGen23])
            profile.maxDeltaBgThreshold = rng.pick([dec("0.2"), dec("0.3")])

            var preferences = Preferences()
            preferences.curve = .rapidActing
            let dynamic = rng.chance(20)
            preferences.useNewFormula = dynamic
            preferences.sigmoid = dynamic && rng.chance(50)

            let glucose = rng.decimal(45 ... 380, 1)
            let delta = rng.decimal(-150 ... 150, 10)
            let glucoseStatus = GlucoseStatus(
                delta: delta,
                glucose: glucose,
                noise: 1,
                shortAvgDelta: delta + rng.decimal(-30 ... 30, 10),
                longAvgDelta: delta + rng.decimal(-50 ... 50, 10),
                date: now,
                lastCalIndex: nil,
                device: "test"
            )

            // IOB decaying to 0 over 4 hours
            let iob0 = rng.decimal(-200 ... 900, 100)
            let peakShift = rng.decimal(50 ... 200, 100)
            let duration: Int
            switch rng.int(0 ... 4) {
            case 0: duration = 0
            case 1: duration = rng.int(1 ... 5)
            case 2: duration = rng.int(6 ... 20)
            case 3: duration = rng.int(21 ... 30)
            default: duration = 30
            }
            let tempRate: Decimal
            switch rng.int(0 ... 4) {
            case 0: tempRate = 0
            case 1: tempRate = (scheduled * rng.decimal(0 ... 90, 100)).rounded(scale: 2)
            case 2: tempRate = (scheduled * rng.decimal(90 ... 130, 100)).rounded(scale: 2)
            case 3: tempRate = scheduled
            default: tempRate = (scheduled * rng.decimal(130 ... 400, 100)).rounded(scale: 2)
            }
            let tempStart = now.addingTimeInterval(-Double(30 - min(duration, 30)) * 60)
            let lastTempStart = duration > 0 ? tempStart : now.addingTimeInterval(-3600)
            let lastTemp = IobResult.LastTemp(
                rate: duration > 0 ? tempRate : 0,
                timestamp: lastTempStart,
                started_at: lastTempStart,
                date: UInt64(lastTempStart.timeIntervalSince1970 * 1000),
                duration: 30
            )
            let lastBolusTime: UInt64? = rng.chance(20) ? nil :
                UInt64((now.timeIntervalSince1970 - Double(rng.int(0 ... 3600))) * 1000)
            let iobData: [IobResult] = (0 ..< 48).map { step in
                let fraction = Decimal(48 - step) / 48
                let iob = iob0 * fraction * fraction
                let activity = iob0 * 2 * fraction / (48 * 5) * peakShift
                let time = now.addingTimeInterval(Double(step * 300))
                return IobResult(
                    iob: iob,
                    activity: activity,
                    basaliob: 0,
                    bolusiob: iob,
                    netbasalinsulin: 0,
                    bolusinsulin: 0,
                    time: time,
                    iobWithZeroTemp: IobResult.IobWithZeroTemp(
                        iob: iob - scheduled * Decimal(step) * 5 / 60 / 2,
                        activity: activity,
                        basaliob: 0,
                        bolusiob: iob,
                        netbasalinsulin: 0,
                        bolusinsulin: 0,
                        time: time
                    ),
                    lastBolusTime: step == 0 ? lastBolusTime : nil,
                    lastTemp: step == 0 ? lastTemp : nil
                )
            }
            let currentTemp = TempBasal(duration: duration, rate: tempRate, temp: .absolute, timestamp: now)

            let cob: Decimal = rng.chance(60) ? 0 : rng.decimal(1 ... 100, 1)
            let lastCarbTime = cob > 0 ?
                now.addingTimeInterval(-Double(rng.int(10 ... 180)) * 60).timeIntervalSince1970 * 1000 : 0
            let mealData = ComputedCarbs(
                carbs: cob > 0 ? cob + rng.decimal(0 ... 40, 1) : 0,
                mealCOB: cob,
                currentDeviation: rng.decimal(-50 ... 100, 10),
                maxDeviation: rng.decimal(0 ... 100, 10),
                minDeviation: rng.decimal(-50 ... 0, 10),
                slopeFromMaxDeviation: rng.decimal(-30 ... 0, 10),
                slopeFromMinDeviation: rng.decimal(0 ... 30, 10),
                allDeviations: [0, 1, 2, 3, 4],
                lastCarbTime: lastCarbTime
            )
            let autosens = Autosens(ratio: rng.chance(50) ? 1 : rng.decimal(70 ... 130, 100), newisf: nil)

            let useOverride = rng.chance(25)
            let orefVariables = TrioCustomOrefVariables(
                average_total_data: dynamic ? rng.decimal(200 ... 600, 10) : 0,
                weightedAverage: dynamic ? rng.decimal(200 ... 600, 10) : 0,
                currentTDD: dynamic ? rng.decimal(200 ... 600, 10) : 0,
                past2hoursAverage: dynamic ? rng.decimal(10 ... 60, 10) : 0,
                date: now,
                overridePercentage: Decimal(rng.int(5 ... 20) * 10),
                useOverride: useOverride,
                duration: 60,
                unlimited: false,
                overrideTarget: useOverride && rng.chance(50) ? rng.decimal(80 ... 160, 1) : 0,
                smbIsOff: false,
                advancedSettings: rng.chance(30),
                isfAndCr: useOverride && rng.chance(50),
                isf: useOverride && rng.chance(50),
                cr: false,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: 30,
                uamMinutes: 30
            )

            func determination(limit: Bool) throws -> Determination? {
                var runPreferences = preferences
                runPreferences.iobLimitsInsulinReq = limit
                return try DeterminationGenerator.determineBasal(
                    profile: profile,
                    preferences: runPreferences,
                    currentTemp: currentTemp,
                    iobData: iobData,
                    mealData: mealData,
                    autosensData: autosens,
                    reservoirData: 100,
                    glucoseStatus: glucoseStatus,
                    microBolusAllowed: true,
                    trioCustomOrefVariables: orefVariables,
                    currentTime: now
                )
            }

            let offResult: Determination?
            do {
                offResult = try determination(limit: false)
            } catch {
                threw += 1
                let onThrew = (try? determination(limit: true)) == nil
                #expect(onThrew, "#\(index): off threw, on must too")
                continue
            }
            let onResult = try determination(limit: true)
            let off = try #require(offResult, "#\(index)")
            let on = try #require(onResult, "#\(index)")

            var testCase = IobLimitPipeline.Case()
            testCase.name = "seed \(String(seed, radix: 16)) #\(index) bg \(glucose) delta \(delta) iob \(iob0) " +
                "temp \(tempRate)@\(duration)m cob \(cob) dynamic \(dynamic)"
            let pair = IobLimitPipeline.Pair(
                testCase: testCase,
                off: IobLimitPipeline.Outcome(
                    determination: off,
                    currentTemp: currentTemp,
                    profile: profile,
                    orefVariables: orefVariables
                ),
                on: IobLimitPipeline.Outcome(
                    determination: on,
                    currentTemp: currentTemp,
                    profile: profile,
                    orefVariables: orefVariables
                )
            )
            let boundBefore = stats.bound
            IobLimitPipeline.check(pair, clock: now, stats: &stats)
            if stats.bound > boundBefore {
                if dynamic { dynamicBound += 1 }
                if cob > 0 { cobBound += 1 }
            } else {
                // every encoded field identical, not just the dosing ones
                let offJSON = try ParityHarness.normalizeDeterminationId(ParityHarness.canonicalJSON(off))
                let onJSON = try ParityHarness.normalizeDeterminationId(ParityHarness.canonicalJSON(on))
                if offJSON != onJSON || off.cobProjection != on.cobProjection {
                    jsonDifferences += 1
                }
            }
        }

        let summary = "seed \(String(seed, radix: 16)): \(stats), threw \(threw), bound with dynamic ISF \(dynamicBound), " +
            "with COB \(cobBound), JSON differences when not bound \(jsonDifferences); " +
            "\(Int(Date().timeIntervalSince(started) * 1000)) ms"
        print("IOB limit generator randomized: " + summary)
        #expect(jsonDifferences == 0, "\(summary)")
        // never vacuous: each seed binds in well over 10% of its cases, with COB and with dynamic ISF
        #expect(stats.bound * 10 >= stats.cases, "\(summary)")
        #expect(stats.boundToZero > 0, "\(summary)")
        #expect(cobBound > 0, "\(summary)")
        #expect(dynamicBound > 0, "\(summary)")
    }
}

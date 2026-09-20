| log | round | start | done | proved | not proved | refuted | goals proved | goals with CTI |
|---|---|---|---|---|---|---|---|---|
| h3loop.log.pre-fix1 | 34 | 17:51 |  | CtiCirLengthAgreesRaw, CtiGhostTracksMscratch, CtiMwResultIsRegfile, CtiRs1SelectTracksRd, CtiRs2SelectTracksRd | CtiFollowerPostIsDutMscratch, CtiGhostTracksMscratch, CtiMemopIsLoadStoreWord, CtiRawLoadDecompressesToLoad, CtiRawStoreDecompressesToStore, CtiRs1BypassIsPreRegs (+10) | CtiRs2BypassIsPreRegs |  |  |
| h3loop.log.pre-fix1 | round5 | 19:38 | 20:41 | CtiGhostTracksMscratch, CtiMStoreHasNoRd, CtiXStoreHasNoRd | CtiFollowerPostIsDutMscratch, CtiGhostTracksMscratch, CtiRs1BypassIsPreRegs, CtiRs2BypassIsPreRegsV2, CtiStoreDataIsRegfile |  |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMscratch (+2) |
| h3loop.log.pre-fix1 | round6 | 20:41 | 21:53 | CtiDExceptLegal, CtiDMemopLegal, CtiGhostTracksMscratch, CtiRs1BypassIsPreRegs, CtiRs2BypassIsPreRegsV2, CtiXmExceptLegal (+1) | CtiFollowerPostIsDutMscratchV2, CtiGhostTracksMscratch, CtiStoreDataIsRegfile |  |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMscratch (+2) |
| h3loop.log.pre-fix1 | round7 | 21:53 | 23:04 | CtiCirInvalidAgreesRaw, CtiCirUopFlagsZero, CtiGhostTracksMscratch, CtiRs2StoreBypassIsPreRegs | CtiFollowerPostIsDutMscratchV2, CtiGhostTracksMscratch, CtiStoreDataIsRegfile |  |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMscratch (+2) |
| h3loop.log.pre-fix1 | round8 | 23:04 | 00:17 | CtiGhostTracksMscratch, CtiNoBreakFlags, CtiStoreDataIsRegfile, CtiXmSleepImpliesNoMemop | CtiFollowerPostIsDutMscratchV2, CtiGhostTracksMscratch | WrapMstatus |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMcause (+6) |
| h3loop.log.pre-fix1 | round9 | 00:17 | 00:59 | CtiFollowerPostIsDutMscratchV2, CtiGhostTracksMscratch, CtiRs1PredecodeAgreesCir32, CtiRs2PredecodeAgreesCir32 |  | WrapMstatus | WrapMscratch | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMcause (+5) |
| h3loop.log.pre-fix1 | round10 | 01:00 | 01:51 | CtiGhostTracksMie, CtiMieChangeIsQuery, CtiSpecMieFrame |  | CtiFollowerPostIsDutMie, WrapMstatus | WrapMie | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMcause (+4) |
| h3loop.log.pre-fix1 | round11 | 05:38 | 06:11 | CtiGhostTracksMtvec, CtiMtvecChangeIsQuery, CtiSpecMtvecFrame |  |  | WrapMtvec | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMcause (+4) |
| h3loop.log.pre-fix1 | round12 | 06:11 | 07:12 | CtiSpecMcauseFrame, CtiSpecMepcFrame | CtiRs1PredecodeAgreesCir16, CtiRs2PredecodeAgreesCir16 | CtiGhostTracksMcause, CtiGhostTracksMepc, CtiGhostTracksPc |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMcause (+4) |
| h3loop.log.pre-fix1 | round13 | 07:12 | 08:10 | CtiNoProgressDuringExcEntry | CtiGhostTracksMepcV2, CtiGhostTracksPcV2, CtiRs1PredecodeAgreesCir16V2, CtiRs2PredecodeAgreesCir16V2 | CtiGhostTracksMcauseV2 |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapMcause (+4) |
| h3loop.log.pre-fix1 | round14 | 08:10 | 09:08 | CtiCirVldTracksBufLevel | CtiRs1PredecodeAgreesCir16V2, CtiRs2PredecodeAgreesCir16V2 |  |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapRegA (+1) |
| h3loop.log.pre-fix1 | round15 | 09:08 | 09:09 | CtiRs1PredecodeAgreesCir16V3, CtiRs2PredecodeAgreesCir16V3 |  |  |  |  |
| h3loop.log.pre-fix1 | round16 | 09:11 | 09:35 |  |  |  |  | LoadAddr, StoreAddr, StoreBe, StoreEn, StoreWData, WrapRegA (+1) |
| h3loop.log.pre-fix2 | round17 | 12:08 | 12:46 | CtiGhostMstatusHardwiredZero, CtiMstatusHardwiredZero, CtiSpecMstatusFrame | CtiGhostTracksMcauseV2, CtiGhostTracksMepcV2, CtiGhostTracksMstatusV2, CtiGhostTracksPcV2, CtiSpecPostMstatusHardwiredZero |  |  | WrapMcause, WrapMepc, WrapMstatus, WrapPc |
| h3loop.log.pre-fix2 | round18 | 12:46 | 13:31 | CtiWbAdd, CtiWbAddi, CtiWbLui, CtiWbXor | CtiCirIsDecompressedRaw |  |  | LoadAddr, StoreAddr |
| h3loop.log.pre-fix2 | round19 | 13:31 | 13:54 | CtiCirInvalidIsDecompressedRaw, CtiCirIsDecompressedRawV2 |  |  | LoadAddr, StoreAddr |  |
| h3loop.log.pre-fix2 | round20 | 13:55 | 14:30 | CtiWbAnd, CtiWbAuipc, CtiWbOr, CtiWbSll, CtiWbSlli, CtiWbSlt (+5) | CtiWbSub |  |  |  |
| h3loop.log.pre-fix2 | round21 | 14:31 | 15:02 | CtiSpecPostMstatusHardwiredZero, CtiWbAndi, CtiWbJal, CtiWbJalr, CtiWbOri, CtiWbSlti (+2) |  |  | LoadAddr, StoreAddr | WrapRegA |
| h3loop.log.pre-fix2 | round22 | 15:02 | 15:15 |  |  | SpecEnUnreach | LoadEn, MemWe, NoMem, StoreBe, StoreEn, StoreWData | WrapMcause, WrapMepc, WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round23 | 15:15 | 15:46 | CtiWbCAdd, CtiWbCAddi, CtiWbCAddi4spn, CtiWbCAnd, CtiWbCAndi, CtiWbCJal (+11) |  |  |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round24 | 15:47 | 16:37 | CtiFolSpecWxAddrIsRd | CtiRegMatch01, CtiRegMatch02, CtiRegMatch03, CtiRegMatch04, CtiRegMatch05, CtiRegMatch06 (+25) | CtiFolSpecWxEnIsRd |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round25 | 16:37 | 17:01 |  | CtiWbLoad | CtiWbCsr |  |  |
| h3loop.log.pre-fix2 | round26 | 17:02 | 17:58 | CtiGhostDroppedForExceptingWrite, CtiWbCsrV2 | CtiRegMatch01, CtiRegMatch02, CtiRegMatch03, CtiRegMatch04, CtiRegMatch05, CtiRegMatch06 (+25) | CtiFolSpecWxEnIsRdV2, CtiFolXExceptNoSpecWrite |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round27 | 17:58 | 18:41 | CtiXmMemAligned | CtiWbLoad |  |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round28 | 18:41 | 19:38 | CtiFolSpecWxEnIsRdV3, CtiFolXExceptNoSpecWriteV2 | CtiRegMatchV2_01, CtiRegMatchV2_02, CtiRegMatchV2_03, CtiRegMatchV2_04, CtiRegMatchV2_05, CtiRegMatchV2_06 (+25) |  |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round29 | 19:38 | 20:21 | CtiFolLoadMemopMatches | CtiWbLoad |  |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round30 | 20:21 | 21:17 | CtiFolMemopNoneUnlessMem, CtiGhostDroppedForUnspecifiable | CtiRegMatchV2_01, CtiRegMatchV2_02, CtiRegMatchV2_03, CtiRegMatchV2_04, CtiRegMatchV2_05, CtiRegMatchV2_06 (+25) |  |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round31 | 21:17 | 22:02 | CtiFolLoadWxIsPick | CtiWbLoad |  |  | WrapRegA, WrapRegB |
| h3loop.log.pre-fix2 | round32 | 22:03 | 22:28 | CtiFolLoadSpecReads, CtiWbAll, CtiWbLoad, CtiWbMulDiv (axiom) |  | CtiFolWriteCoverage |  |  |
| h3loop.log.pre-fix2 | round33 | 22:28 | 23:09 | CtiFolWriteCoverageV2, CtiRegMatchV2_01, CtiRegMatchV2_02, CtiRegMatchV2_03, CtiRegMatchV2_04, CtiRegMatchV2_05 (+26) |  |  | WrapRegA, WrapRegB |  |
| h3loop.log.pre-fix2 | round34 | 23:11 | 23:19 |  |  |  |  | WrapMcause, WrapMepc, WrapMstatus, WrapPc |
| h3loop.log.pre-fix2 | round35 | 23:22 | 23:46 |  | CtiGhostTracksMcauseV2, CtiGhostTracksMepcV2, CtiGhostTracksMstatusV2, CtiGhostTracksPcV2 |  |  |  |
| h3loop.log.pre-fix2 | round36 | 23:46 | 00:28 | CtiGhostTracksMcauseV3, CtiGhostTracksMstatusV3, CtiIrqMcauseAgrees, CtiIrqMepcAgrees, CtiIrqMstatusAgrees, CtiMretMcauseUntouched (+6) | CtiGhostTracksMepcV3, CtiGhostTracksPcV3, CtiTrapMepcAgrees | CtiIrqPcAgrees | WrapMcause, WrapMstatus | WrapMepc, WrapPc |
| h3loop.log.pre-fix2 | round37 | 00:28 | 01:13 | CtiGhostTracksMepcV3, CtiPcEven, CtiTrapMepcAgreesV2 | CtiFolPcEven |  | WrapMepc |  |
| h3loop.log.pre-fix2 | round38 | 05:48 | 06:12 | CtiJumpTargetAgrees | CtiGhostTracksPcV4, CtiSeqNextPcAgrees |  |  |  |
| h3loop.log | round39 | 09:10 | 09:57 | CtiGhostTracksPcV4, CtiSeqNextPcAgreesV2 | CtiGhostTracksPcV4, CtiLockedJumpTargetAgrees |  |  | WrapPc |
| h3loop.log | round40 | 09:57 | 10:56 | CtiGhostTracksPcV4, CtiLockedJumpTargetAgrees | CtiLockImpliesTakenJump, CtiLockedJumpTargetAgrees |  |  | WrapPc |
| h3loop.log | round41 | 10:57 | 11:28 | CtiLockCirValid, CtiLockImpliesJumpOrBranch | CtiLockImpliesTakenJump, CtiLockNoRawHazard |  |  |  |
| h3loop.log | round43 | 11:28 | 11:44 | CtiLockNoRawHazard |  |  |  |  |
| h3loop.log | round44 | 11:46 | 12:01 |  |  |  |  |  |
| h3loop.log | round45 | 12:01 | 12:16 |  |  |  |  |  |
| h3loop.log | round46 | 12:17 | 12:32 | CtiRs1BypassIsPreRegsClean, CtiRs2BypassIsPreRegsClean |  |  |  |  |
| h3loop.log | round47 | 12:32 | 12:48 | CtiRs1BypassIsPreRegsV3, CtiRs2BypassIsPreRegsV3 |  |  |  |  |
| h3loop.log | round48 | 12:51 | 12:57 | CtiLockCirClean, CtiLockImpliesTakenJump |  |  |  |  |
| h3loop.log | round42 | 12:57 | 13:29 | CtiGhostTracksPcV4, CtiLockedJumpTargetAgrees |  |  | WrapPc |  |

#include "boltzplatz.h"

MODULE MOD_Particle_Analyze
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
#ifdef PARTICLES
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE InitParticleAnalyze
  MODULE PROCEDURE InitParticleAnalyze
END INTERFACE

INTERFACE FinalizeParticleAnalyze
  MODULE PROCEDURE FinalizeParticleAnalyze
END INTERFACE

INTERFACE AnalyzeParticles
  MODULE PROCEDURE AnalyzeParticles
END INTERFACE

INTERFACE CalcKineticEnergy
  MODULE PROCEDURE CalcKineticEnergy
END INTERFACE

INTERFACE CalcShapeEfficiencyR
  MODULE PROCEDURE CalcShapeEfficiencyR
END INTERFACE

INTERFACE CalcEkinPart
  MODULE PROCEDURE CalcEkinPart
END INTERFACE

PUBLIC:: InitParticleAnalyze, FinalizeParticleAnalyze!, CalcPotentialEnergy
PUBLIC:: CalcKineticEnergy, CalcEkinPart, AnalyzeParticles
#if (PP_TimeDiscMethod == 42)
PUBLIC :: ElectronicTransition, WriteEletronicTransition
#endif
!===================================================================================================================================

CONTAINS

SUBROUTINE InitParticleAnalyze()
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
  USE MOD_Globals
  USE MOD_Preproc
  USE MOD_Analyze_Vars            ,ONLY: DoAnalyze
  USE MOD_Particle_Analyze_Vars  !,ONLY:ParticleAnalyzeInitIsDone, CalcCharge, CalcEkin, CalcEpot 
  USE MOD_ReadInTools             ,ONLY: GETLOGICAL, GETINT, GETSTR, GETINTARRAY, GETREALARRAY, GETREAL
  USE MOD_Particle_Vars           ,ONLY: nSpecies
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER   :: dir, VeloDirs_hilf(4)
!===================================================================================================================================
  IF (ParticleAnalyzeInitIsDone) THEN
CALL abort(__STAMP__,&
'InitParticleAnalyse already called.',999,999.)
    RETURN
  END IF
  SWRITE(UNIT_StdOut,'(132("-"))')
  SWRITE(UNIT_stdOut,'(A)') ' INIT PARTICLE ANALYZE...'

  PartAnalyzeStep = GETINT('Part-AnalyzeStep','1')
  IF (PartAnalyzeStep.EQ.0) PartAnalyzeStep = 123456789

  DoAnalyze = .FALSE.
  CalcEpot = GETLOGICAL('CalcPotentialEnergy','.FALSE.')
  IF(CalcEpot) DoAnalyze = .TRUE.
  DoVerifyCharge = GETLOGICAL('PIC-VerifyCharge','.FALSE.')
  CalcCharge = GETLOGICAL('CalcCharge','.FALSE.')
  IF(CalcCharge) DoAnalyze = .TRUE. 
  CalcEkin = GETLOGICAL('CalcKineticEnergy','.FALSE.')
  CalcEint = GETLOGICAL('CalcInternalEnergy','.FALSE.')
  CalcTemp = GETLOGICAL('CalcTemp','.FALSE.')
  IF(CalcTemp.OR.CalcEint) DoAnalyze = .TRUE.
  IF(CalcEkin) THEN
    DoAnalyze = .TRUE.
    IF (nSpecies .GT. 1) THEN
      nEkin = nSpecies + 1
    ELSE
     nEkin = 1
    END IF
  END IF
  CalcPartBalance = GETLOGICAL('CalcPartBalance','.FALSE.')
  IF (CalcPartBalance) THEN
    DoAnalyze = .TRUE.
    SDEALLOCATE(nPartIn)
    SDEALLOCATE(nPartOut)
    SDEALLOCATE(PartEkinIn)
    SDEALLOCATE(PartEkinOut)
    ALLOCATE( nPartIn(nSpecies)     &
            , nPartOut(nSpecies)    &
            , PartEkinOut(nSpecies) &
            , PartEkinIn(nSpecies)  )
    nPartIn=0
    nPartOut=0
    PartEkinOut=0.
    PartEkinIn=0.
#if defined(LSERK) || defined(IMEX) || defined(IMPA) 
    SDEALLOCATE( nPartInTmp)
    SDEALLOCATE( PartEkinInTmp)
    ALLOCATE( nPartInTmp(nSpecies)     &
            , PartEkinInTmp(nSpecies)  )
    PartEkinInTmp=0.
    nPartInTmp=0
#endif
  END IF
  CalcVelos = GETLOGICAL('CalcVelos','.FALSE')
  IF (CalcVelos) THEN
    DoAnalyze=.TRUE.
    VeloDirs_hilf = GetIntArray('VelocityDirections',4,'1,1,1,1') ! x,y,z,abs -> 0/1 = T/F
    VeloDirs(:) = .FALSE.
    DO dir = 1,4
      IF (VeloDirs_hilf(dir) .EQ. 1) THEN
        VeloDirs(dir) = .TRUE.
      END IF
    END DO
    IF ((.NOT. VeloDirs(1)) .AND. (.NOT. VeloDirs(2)) .AND. &
        (.NOT. VeloDirs(3)) .AND. (.NOT. VeloDirs(4))) THEN
      CALL abort(&
        __STAMP__&
        ,'No VelocityDirections set in CalcVelos!')
    END IF
  END IF
  TrackParticlePosition = GETLOGICAL('Part-TrackPosition','.FALSE.')
  IF(TrackParticlePosition)THEN
    printDiff=GETLOGICAL('printDiff','.FALSE.')
    IF(printDiff)THEN
      printDiffTime=GETREAL('printDiffTime','12.')
      printDiffVec=GETREALARRAY('printDiffVec',6,'0.,0.,0.,0.,0.,0.')
    END IF
  END IF
  CalcNumSpec   = GETLOGICAL('CalcNumSpec','.FALSE.')
  CalcCollRates = GETLOGICAL('CalcCollRates','.FALSE.')
  CalcReacRates = GETLOGICAL('CalcReacRates','.FALSE.')
  IF(CalcNumSpec.OR.CalcCollRates.OR.CalcReacRates) DoAnalyze = .TRUE.
  CalcShapeEfficiency = GETLOGICAL('CalcShapeEfficiency','.FALSE.')
  IF (CalcShapeEfficiency) THEN
    DoAnalyze = .TRUE.
    CalcShapeEfficiencyMethod = GETSTR('CalcShapeEfficiencyMethod','AllParts')
    SELECT CASE(CalcShapeEfficiencyMethod)
    CASE('AllParts')  ! All currently available Particles are used
    CASE('SomeParts') ! A certain percentage of currently available Particles is used
      ShapeEfficiencyNumber = GETINT('ShapeEfficiencyNumber','100')  ! in percent
    CASE DEFAULT
      CALL abort(&
          __STAMP__&
          , ' CalcShapeEfficiencyMethod not implemented: ')

    END SELECT
  END IF

  IsRestart = GETLOGICAL('IsRestart','.FALSE.')

  ParticleAnalyzeInitIsDone=.TRUE.

  SWRITE(UNIT_stdOut,'(A)')' INIT PARTCILE ANALYZE DONE!'
  SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitParticleAnalyze

SUBROUTINE AnalyzeParticles(Time)
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
  USE MOD_Globals
  USE MOD_Preproc
  USE MOD_Analyze_Vars,          ONLY: DoAnalyze
  USE MOD_Particle_Analyze_Vars!,ONLY: ParticleAnalyzeInitIsDone,CalcCharge,CalcEkin,IsRestart
  USE MOD_PARTICLE_Vars,         ONLY: PartSpecies, PDM, nSpecies, PartMPF, usevMPF, BoltzmannConst
#if (PP_TimeDiscMethod==42)
  USE MOD_PARTICLE_Vars,         ONLY: Species
#endif
  USE MOD_DSMC_Vars,             ONLY: DSMC, CollInf, useDSMC, CollisMode, ChemReac, SpecDSMC, PolyatomMolDSMC
  USE MOD_Restart_Vars,          ONLY: DoRestart
  USE MOD_AnalyzeField,          ONLY: CalcPotentialEnergy
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
  USE MOD_TimeDisc_Vars,         ONLY : iter
#endif
  USE MOD_PIC_Analyze,           ONLY: CalcDepositedCharge
#ifdef MPI
  USE MOD_LoadBalance_Vars,      ONLY: tCurrent
  USE MOD_Particle_MPI_Vars,     ONLY: PartMPI
#endif /*MPI*/
#if ( PP_TimeDiscMethod ==42)
  USE MOD_DSMC_Vars,             ONLY: Adsorption
#endif
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
  REAL,INTENT(IN)                 :: Time
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  LOGICAL             :: isOpen, FileExists
  CHARACTER(LEN=350)  :: outfile
  INTEGER             :: unit_index, iSpec, iPolyatMole, iPart, iDOF, OutputCounter
  REAL                :: WEl, WMag, NumSpec(nSpecies+1)
  REAL                :: Ekin(nSpecies + 1), Temp(nSpecies+1)
  REAL                :: IntEn(nSpecies,3),IntTemp(nSpecies,3),TempTotal(nSpecies+1), Xi_Vib(nSpecies)
  REAL                :: MaxCollProb, MeanCollProb
#ifdef MPI
  REAL                :: RECBR(nSpecies),RECBR2(nEkin),RECBR1
  INTEGER             :: RECBIM(nSpecies)
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
  REAL                :: sumMeanCollProb
#endif
#if (PP_TimeDiscMethod==42)
  REAL                :: sumIntTemp(nSpecies),sumIntEn(nSpecies)
#endif
#endif /*MPI*/
  REAL, ALLOCATABLE   :: CRate(:), RRate(:)
#if (PP_TimeDiscMethod ==42)
  INTEGER             :: ii, iunit, iCase, iTvib,jSpec, WallNumSpec(nSpecies)
  CHARACTER(LEN=64)   :: DebugElectronicStateFilename
  CHARACTER(LEN=350)  :: hilf
  REAL                :: WallCoverage(nSpecies), Adsorptionrate(nSpecies), Desorptionrate(nSpecies)
#endif
  REAL                :: PartVtrans(nSpecies,4) ! macroscopic velocity (drift velocity) A. Frohn: kinetische Gastheorie
  REAL                :: PartVtherm(nSpecies,4) ! microscopic velocity (eigen velocity) PartVtrans + PartVtherm = PartVtotal
  INTEGER             :: dir
#ifdef MPI 
! load balance
  REAL                :: tLBStart,tLBEnd
#endif /*MPI*/
!===================================================================================================================================
  IF ( DoRestart ) THEN
    isRestart = .true.
  END IF
  IF (DoAnalyze) THEN
#ifdef MPI 
  tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
!SWRITE(UNIT_StdOut,'(132("-"))')
!SWRITE(UNIT_stdOut,'(A)') ' PERFORMING PARTICLE ANALYZE...'
    IF (useDSMC) THEN
      IF (CollisMode.NE.0) THEN
        SDEALLOCATE(CRate)
        ALLOCATE(CRate(CollInf%NumCase + 1))
        IF (CollisMode.EQ.3) THEN
          SDEALLOCATE(RRate)
          ALLOCATE(RRate(ChemReac%NumOfReact))
          RRate = 0.0
        END IF
      END IF
    END IF
  OutputCounter = 2
  unit_index = 535
#ifdef MPI
!#ifdef PARTICLES
  IF (PartMPI%MPIRoot) THEN
#endif    /* MPI */
    INQUIRE(UNIT   = unit_index , OPENED = isOpen)
    IF (.NOT.isOpen) THEN
#if (PP_TimeDiscMethod==42)
    ! if only the reaction rate is desired (resevoir) the initial temperature
    ! of the second species is added to the filename
      IF (DSMC%ReservoirSimuRate) THEN
        IF ( SpecDSMC(1)%InterID .EQ. 2 .OR. SpecDSMC(1)%InterID .EQ. 20 ) THEN
          iTvib = INT(SpecDSMC(1)%Init(0)%Tvib)
          WRITE( hilf, '(I5.5)') iTvib
          outfile = 'Database_Tvib_'//TRIM(hilf)//'.csv'
        ELSE
          !iTvib = INT(SpecDSMC(1)%Telec )
          iTvib = INT(Species(1)%Init(0)%MWTemperatureIC) !wrong name, if MWTemp is defined in %Init!!!
          WRITE( hilf, '(I5.5)') iTvib
          outfile = 'Database_Ttrans_'//TRIM(hilf)//'.csv'
        END IF
      ELSE
        outfile = 'Database.csv'
      END IF
#else
      outfile = 'Database.csv'
#endif

      INQUIRE(file=TRIM(outfile),EXIST=FileExists)
      IF (isRestart .and. FileExists) THEN
        OPEN(unit_index,file=TRIM(outfile),position="APPEND",status="OLD")
        !CALL FLUSH (unit_index)
      ELSE
        OPEN(unit_index,file=TRIM(outfile))
        !CALL FLUSH (unit_index)
        !--- insert header
        WRITE(unit_index,'(A6,A5)',ADVANCE='NO') 'TIME', ' '
        IF (CalcNumSpec) THEN
          DO iSpec = 1, nSpecies + 1
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A12,I3.3,A5)',ADVANCE='NO') OutputCounter,'-nPart-Spec-', iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
        END IF
        IF (CalcCharge) THEN
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A12,A5)',ADVANCE='NO') OutputCounter,'-Charge     '
          OutputCounter = OutputCounter + 1
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A16,A5)',ADVANCE='NO') OutputCounter,'-Charge-absError'
          OutputCounter = OutputCounter + 1
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A16,A5)',ADVANCE='NO') OutputCounter,'-Charge-relError'
          OutputCounter = OutputCounter + 1
        END IF
        IF (CalcPartBalance) THEN
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A14,I3.3,A5)',ADVANCE='NO') OutputCounter,'-nPartIn-Spec-',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A15,I3.3,A5)',ADVANCE='NO') OutputCounter,'-nPartOut-Spec-',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
        END IF
        IF (CalcEpot) THEN 
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A11)',ADVANCE='NO') OutputCounter,'-W-El      '
          OutputCounter = OutputCounter + 1
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A11)',ADVANCE='NO') OutputCounter,'-W-Mag    '
          OutputCounter = OutputCounter + 1
        END IF
        IF (CalcEkin) THEN
          DO iSpec=1, nEkin
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-Ekin-',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
        END IF
        IF (CalcTemp) THEN
          DO iSpec=1, nSpecies + 1
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' -TempTra-',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
        END IF
        IF (CalcVelos) THEN
          DO iSpec=1, nSpecies
            IF (VeloDirs(1)) THEN
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Velo_Xtrans',iSpec,' '
              OutputCounter = OutputCounter + 1
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Velo_Xtherm',iSpec,' '
              OutputCounter = OutputCounter + 1
            END IF
            IF (VeloDirs(2)) THEN
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Velo_Ytrans',iSpec,' '
              OutputCounter = OutputCounter + 1
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Velo_Ytherm',iSpec,' '
              OutputCounter = OutputCounter + 1
            END IF
            IF (VeloDirs(3)) THEN
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Velo_Ztrans',iSpec,' '
              OutputCounter = OutputCounter + 1
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Velo_Ztherm',iSpec,' '
              OutputCounter = OutputCounter + 1
            END IF
            IF (VeloDirs(4)) THEN
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' AbsVelo_trans',iSpec,' '
              OutputCounter = OutputCounter + 1
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' AbsVelo_therm',iSpec,' '
              OutputCounter = OutputCounter + 1
            END IF
          END DO
        END IF
        IF (CalcPartBalance) THEN
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A8,I3.3,A5)',ADVANCE='NO') OutputCounter,'-EkinIn-',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A9,I3.3,A5)',ADVANCE='NO') OutputCounter,'-EkinOut-',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
        END IF
#if (PP_TimeDiscMethod==1000)
        IF (CollisMode.GT.1) THEN
          DO iSpec=1, nSpecies         
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' EVib',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' ERot',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          IF ( DSMC%ElectronicModel ) THEN
            DO iSpec = 1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' EElec',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
          END IF
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' TempVib',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec=1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' TempRot',iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
        END IF
#endif
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || PP_TimeDiscMethod==300 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
        IF (CollisMode.GT.1) THEN
          IF(CalcEint) THEN
            DO iSpec=1, nSpecies         
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-EVib',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
            DO iSpec=1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-ERot',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
            IF (DSMC%ElectronicModel) THEN
              DO iSpec = 1, nSpecies
                WRITE(unit_index,'(A1)',ADVANCE='NO') ','
                WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-EElec',iSpec,' '
                OutputCounter = OutputCounter + 1
              END DO
            END IF
          END IF
          IF(CalcTemp) THEN
            DO iSpec=1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-TempVib',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
            DO iSpec=1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-XiVibMean',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
            DO iSpec=1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-TempRot',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
            DO iSpec=1, nSpecies+1
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-TempTotal',iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
            IF ( DSMC%ElectronicModel ) THEN
              DO iSpec=1, nSpecies
                WRITE(unit_index,'(A1)',ADVANCE='NO') ','
                WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-TempElec',iSpec,' '
                OutputCounter = OutputCounter + 1
              END DO
            END IF
          END IF
        END IF
        IF(DSMC%CalcQualityFactors) THEN
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A,A5)',ADVANCE='NO') OutputCounter,'-Pmean',' '
          OutputCounter = OutputCounter + 1
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A,A5)',ADVANCE='NO') OutputCounter,'-Pmax',' '
          OutputCounter = OutputCounter + 1
        END IF
#endif
#if (PP_TimeDiscMethod==42)
        IF (DSMC%WallModel.GE.1) THEN
!                 IF (CalcWallNumSpec) THEN
            DO iSpec = 1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-nPart-Wall-Spec-', iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
!                 END IF
!                 IF (CalcWallCoverage) THEN
            DO iSpec = 1, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,'-Surf-Cov-', iSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
!                 END IF
          DO iSpec = 1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Pads', iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec = 1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Pdes', iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec = 1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Nads', iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          DO iSpec = 1, nSpecies
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Ndes', iSpec,' '
            OutputCounter = OutputCounter + 1
          END DO
          IF (Adsorption%TPD) THEN
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' WallTemp', iSpec,' '
          END IF
          OutputCounter = OutputCounter + 1
        END IF
        IF(CalcCollRates) THEN
          DO iSpec = 1, nSpecies
            DO jSpec = iSpec, nSpecies
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' CollRate', iSpec, '+', jSpec,' '
              OutputCounter = OutputCounter + 1
            END DO
          END DO
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,'(I3.3,A,A5)',ADVANCE='NO') OutputCounter,' TotalCollRate',' '
          OutputCounter = OutputCounter + 1
        END IF
        IF(CalcReacRates) THEN
          IF(CollisMode.EQ.3) THEN
            DO iCase=1, ChemReac%NumOfReact
              WRITE(unit_index,'(A1)',ADVANCE='NO') ','
              WRITE(unit_index,'(I3.3,A,I3.3,A5)',ADVANCE='NO') OutputCounter,' Reaction', iCase,' '
              OutputCounter = OutputCounter + 1
            END DO
          END IF
        END IF
#endif
        WRITE(unit_index,'(A1)') ' '
      END IF
    END IF
#ifdef MPI
  END IF
#endif    /* MPI */

!===================================================================================================================================
! Analyze Routines
!===================================================================================================================================
! Calculate particle number per species and total number of particles
  NumSpec = 0
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
      IF (usevMPF) THEN 
        NumSpec(PartSpecies(iPart)) = NumSpec(PartSpecies(iPart)) + PartMPF(iPart)          ! NumSpec = real particle number
      ELSE
        NumSpec(PartSpecies(iPart)) = NumSpec(PartSpecies(iPart)) + 1                       ! NumSpec = simulation particle number
      END IF
    END IF
  END DO
  NumSpec(nSpecies + 1) = SUM(NumSpec)
!-----------------------------------------------------------------------------------------------------------------------------------
! Calculate total temperature of each molecular species (Laux, p. 109)
  IF(CalcTemp) THEN
    CALL CalcTemperature(Temp, NumSpec)
    IF (CollisMode.GT.1) THEN
      CALL CalcIntTempsAndEn(IntTemp, IntEn)
      TempTotal = 0.0
      Xi_Vib = 0.0
      DO iSpec = 1, nSpecies
        IF(((SpecDSMC(iSpec)%InterID.EQ.2).OR.(SpecDSMC(iSpec)%InterID.EQ.20)).AND.(NumSpec(iSpec).GT.0)) THEN
          IF(SpecDSMC(iSpec)%PolyatomicMol) THEN
            IF(IntTemp(iSpec,1).GT.0) THEN
              iPolyatMole = SpecDSMC(iSpec)%SpecToPolyArray
              DO iDOF = 1, PolyatomMolDSMC(iPolyatMole)%VibDOF
                Xi_Vib(iSpec) = Xi_Vib(iSpec) + 2*PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF)/IntTemp(iSpec,1) &
                              /(exp(PolyatomMolDSMC(iPolyatMole)%CharaTVibDOF(iDOF)/IntTemp(iSpec,1)) - 1)
              END DO
            ELSE
              Xi_Vib(iSpec) = 0.0
            END IF
            TempTotal(iSpec) = (3*Temp(iSpec)+SpecDSMC(iSpec)%Xi_Rot*IntTemp(iSpec,2) &
                                + Xi_Vib(iSpec)*IntTemp(iSpec,1)) &
                                / (3+SpecDSMC(iSpec)%Xi_Rot+Xi_Vib(iSpec))
          ELSE
            IF(IntTemp(iSpec,1).GT.0) THEN
              Xi_Vib(iSpec) = 2*SpecDSMC(iSpec)%CharaTVib/IntTemp(iSpec,1)/(exp(SpecDSMC(iSpec)%CharaTVib/IntTemp(iSpec,1)) - 1)
            ELSE
              Xi_Vib(iSpec) = 0.0
            END IF
            TempTotal(iSpec) = (3*Temp(iSpec) + 2*IntTemp(iSpec,2) + Xi_Vib(iSpec)*IntTemp(iSpec,1))/(5+Xi_Vib(iSpec))
          END IF
        ELSE
          TempTotal(iSpec) = Temp(iSpec)
        END IF
        TempTotal(nSpecies+1) = TempTotal(nSpecies+1) + TempTotal(iSpec)*NumSpec(iSpec)
      END DO
      TempTotal(nSpecies+1) = TempTotal(nSpecies+1) / NumSpec(nSpecies+1)
    END IF
  ELSEIF(CalcEint.AND.(CollisMode.GT.1)) THEN
    CALL CalcIntTempsAndEn(IntTemp, IntEn)
  END IF
!-----------------------------------------------------------------------------------------------------------------------------------
! Determine the maximal collision probability for whole reservoir and mean collision probability (only for one cell)
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
  IF((iter.GT.0).AND.(DSMC%CalcQualityFactors).AND.(DSMC%CollProbMeanCount.GT.0)) THEN
    MaxCollProb = DSMC%CollProbMax
    MeanCollProb = DSMC%CollProbMean / DSMC%CollProbMeanCount
  ELSE
    MaxCollProb = 0.0
    MeanCollProb = 0.0
  END IF
#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! Other Analyze Routines
  IF(CalcCharge) CALL CalcDepositedCharge() ! mpi communication done in calcdepositedcharge
  !IF(CalcNumSpec) CALL GetNumSpec(NumSpec)
  IF(CalcEpot) CALL CalcPotentialEnergy(WEl,WMag)
  IF(CalcEkin) CALL CalcKineticEnergy(Ekin)
  !IF(CalcTemp) CALL CalcTemperature(Temp, NumSpec)
  IF(TrackParticlePosition) CALL TrackingParticlePosition(time)
  PartVtrans=0.
  PartVtherm=0.
  IF(CalcVelos) CALL CalcVelocities(PartVtrans, PartVtherm)
!===================================================================================================================================
! MPI Communication
!===================================================================================================================================
#ifdef MPI 
  tLBEnd = LOCALTIME() ! LB Time End
  tCurrent(14)=tCurrent(14)+tLBEnd-tLBStart
#endif /*MPI*/

#ifdef MPI 
  tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
  IF(CalcEpot)    CALL CalcPotentialEnergy(WEl,WMag)
#ifdef MPI 
  tLBEnd = LOCALTIME() ! LB Time End
  tCurrent(13)=tCurrent(13)+tLBEnd-tLBStart
#endif /*MPI*/

! MPI Communication
#ifdef MPI
!IF(MPIRoot) THEN
IF (PartMPI%MPIRoot) THEN
#ifdef MPI 
  tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
  IF(CalcNumSpec) &
    CALL MPI_REDUCE(MPI_IN_PLACE,NumSpec,nSpecies,MPI_INTEGER,MPI_SUM,0,PartMPI%COMM,IERROR)
#ifdef MPI 
  tLBEnd = LOCALTIME() ! LB Time End
  tCurrent(14)=tCurrent(14)+tLBEnd-tLBStart
#endif /*MPI*/
  IF (CalcEpot) THEN 
#ifdef MPI 
    tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
    CALL MPI_REDUCE(MPI_IN_PLACE,WEl , 1 , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,WMag, 1 , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
#ifdef MPI 
    tLBEnd = LOCALTIME() ! LB Time End
    tCurrent(13)=tCurrent(13)+tLBEnd-tLBStart
#endif /*MPI*/
  END IF
#ifdef MPI 
  tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
  IF (CalcEkin) &
    CALL MPI_REDUCE(MPI_IN_PLACE,Ekin(:) , nEkin , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
  IF (CalcTemp) THEN
    CALL MPI_REDUCE(MPI_IN_PLACE,Temp   , nSpecies, MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
    Temp = Temp / PartMPI%nProcs
  END IF
  IF (CalcPartBalance)THEN
    CALL MPI_REDUCE(MPI_IN_PLACE,nPartIn(:)    ,nSpecies,MPI_INTEGER         ,MPI_SUM,0,PartMPI%COMM,IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,nPartOUt(:)   ,nSpecies,MPI_INTEGER         ,MPI_SUM,0,PartMPI%COMM,IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,PartEkinIn(:) ,nSpecies,MPI_DOUBLE_PRECISION,MPI_SUM,0,PartMPI%COMM,IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,PartEkinOut(:),nSpecies,MPI_DOUBLE_PRECISION,MPI_SUM,0,PartMPI%COMM,IERROR)
  END IF
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
    ! Determining the maximal (MPI_MAX) and mean (MPI_SUM) collision probabilities
    CALL MPI_REDUCE(MPI_IN_PLACE,MaxCollProb,1, MPI_DOUBLE_PRECISION, MPI_MAX,0, PartMPI%COMM, IERROR)
    CALL MPI_REDUCE(MeanCollProb,sumMeanCollProb,1, MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
    MeanCollProb = sumMeanCollProb / PartMPI%nProcs
#endif
ELSE ! no Root
#ifdef MPI 
  tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
  IF(CalcNumSpec) &
    CALL MPI_REDUCE(NumSpec,RECBIM,nSpecies,MPI_INTEGER,MPI_SUM,0,PartMPI%COMM,IERROR)
#ifdef MPI 
  tLBEnd = LOCALTIME() ! LB Time End
  tCurrent(14)=tCurrent(14)+tLBEnd-tLBStart
#endif /*MPI*/
  IF (CalcEpot) THEN 
#ifdef MPI 
    tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
    CALL MPI_REDUCE(WEl,RECBR1  ,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,PartMPI%COMM, IERROR)
    CALL MPI_REDUCE(WMag,RECBR1,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,PartMPI%COMM, IERROR)
#ifdef MPI 
    tLBEnd = LOCALTIME() ! LB Time End
    tCurrent(13)=tCurrent(13)+tLBEnd-tLBStart
#endif /*MPI*/
  END IF
#ifdef MPI 
  tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
  IF (CalcEkin) &
    CALL MPI_REDUCE(Ekin,RECBR2 , nEkin , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
  IF (CalcTemp) &
    CALL MPI_REDUCE(Temp,RECBR   , nSpecies, MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
  IF (CalcPartBalance)THEN
    CALL MPI_REDUCE(nPartIn,RECBR    ,nSpecies,MPI_INTEGER         ,MPI_SUM,0,PartMPI%COMM,IERROR)
    CALL MPI_REDUCE(nPartOut,RECBR   ,nSpecies,MPI_INTEGER         ,MPI_SUM,0,PartMPI%COMM,IERROR)
    CALL MPI_REDUCE(PartEkinIn,RECBR ,nSpecies,MPI_DOUBLE_PRECISION,MPI_SUM,0,PartMPI%COMM,IERROR)
    CALL MPI_REDUCE(PartEkinOut,RECBR,nSpecies,MPI_DOUBLE_PRECISION,MPI_SUM,0,PartMPI%COMM,IERROR)
  END IF
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
    CALL MPI_REDUCE(MaxCollProb,RECBR,1,MPI_DOUBLE_PRECISION,MPI_MAX,0, PartMPI%COMM, IERROR)
    CALL MPI_REDUCE(MeanCollProb,sumMeanCollProb,1,MPI_DOUBLE_PRECISION,MPI_SUM,0, PartMPI%COMM, IERROR)
#endif
#ifdef MPI 
  tLBEnd = LOCALTIME() ! LB Time End
  tCurrent(14)=tCurrent(14)+tLBEnd-tLBStart
#endif /*MPI*/
END IF
#endif

#ifdef MPI 
  tLBEnd = LOCALTIME() ! LB Time End
  tCurrent(14)=tCurrent(14)+tLBEnd-tLBStart
#endif /*MPI*/
#ifdef MPI 
tLBStart = LOCALTIME() ! LB Time Start
#endif /*MPI*/
!-----------------------------------------------------------------------------------------------------------------------------------
#if (PP_TimeDiscMethod==1000)
  IF (CollisMode.GT.1) CALL CalcIntTempsAndEn(IntTemp, IntEn)
#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! Calculate the collision rates and reaction rate coefficients (Arrhenius-type chemistry)
#if (PP_TimeDiscMethod==42)
  IF(CalcCollRates) CALL CollRates(CRate)
  IF(CalcReacRates) THEN
    IF ((CollisMode.EQ.3).AND.(iter.GT.0)) CALL ReacRates(RRate, NumSpec)
  END IF
IF (DSMC%WallModel.GE.1) THEN
  CALL GetWallNumSpec(WallNumSpec,WallCoverage)
  CALL CalcSurfRates(WallNumSpec,Adsorptionrate,Desorptionrate)
END IF
IF (CollisMode.GT.1) CALL CalcIntTempsAndEn(IntTemp, IntEn)
! currently, calculation of internal electronic energy not implemented !
#ifdef MPI
! average over all cells
  IF (CollisMode.GT.1) THEN
    CALL MPI_REDUCE(IntTemp(:,1), sumIntTemp(:) , nSpecies , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
    IntTemp(:,1) = sumIntTemp(:) / PartMPI%nProcs
    CALL MPI_REDUCE(IntTemp(:,2), sumIntTemp(:) , nSpecies , MPI_DOUBLE_PRECISION, MPI_SUM,0,PartMPI%COMM, IERROR)
    IntTemp(:,2) = sumIntTemp(:) / PartMPI%nProcs
    CALL MPI_REDUCE(IntEn(:,1) , sumIntEn(:)   , nSpecies , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
    IntEn(:,1) = sumIntEn(:)
    CALL MPI_REDUCE(IntEn(:,2) , sumIntEn(:)   , nSpecies , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
    IntEn(:,2) = sumIntEn(:) 
    IF ( DSMC%ElectronicModel ) THEN
      CALL MPI_REDUCE(IntTemp(:,3), sumIntTemp(:) , nSpecies , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
      IntTemp(:,3) = sumIntTemp(:) / PartMPI%nProcs
      CALL MPI_REDUCE(IntEN(:,3), sumIntEn(:) , nSpecies , MPI_DOUBLE_PRECISION, MPI_SUM,0, PartMPI%COMM, IERROR)
      IntEn(:,3) = sumIntEn(:)
    END IF
  END IF 
#endif /*MPI*/
#endif /*PP_TimeDiscMethod==42*/
!-----------------------------------------------------------------------------------------------------------------------------------
  IF (CalcShapeEfficiency) CALL CalcShapeEfficiencyR()   ! This will NOT be placed in the file but directly in "out"
!===================================================================================================================================
! Output Routines
!===================================================================================================================================
#ifdef MPI
IF (PartMPI%MPIROOT) THEN
#endif    /* MPI */
  WRITE(unit_index,104,ADVANCE='NO') Time
    IF (CalcNumSpec) THEN
      DO iSpec=1, nSpecies + 1
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') REAL(NumSpec(iSpec))
      END DO
    END IF
    IF (CalcCharge) THEN 
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') PartCharge(1)
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') PartCharge(2)       
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') PartCharge(3)
    END IF
    IF (CalcPartBalance) THEN
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') REAL(nPartIn(iSpec))
      END DO
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') REAL(nPartOut(iSpec))
      END DO
    END IF
    IF (CalcEpot) THEN 
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') WEl
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') WMag
    END IF
    IF (CalcEkin) THEN 
      DO iSpec=1, nEkin
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') Ekin(iSpec)
      END DO
    END IF
    IF (CalcTemp) THEN
      DO iSpec=1, nSpecies + 1
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') Temp(iSpec)
      END DO
    END IF
    IF (CalcVelos) THEN
      DO iSpec=1, nSpecies
        DO dir = 1,4
          IF (VeloDirs(dir)) THEN
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,104,ADVANCE='NO') PartVtrans(iSpec,dir)
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,104,ADVANCE='NO') PartVtherm(iSpec,dir)
          END IF
        END DO
      END DO
    END IF
    IF (CalcPartBalance) THEN
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') PartEkinIn(iSpec)
      END DO
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') PartEkinOut(iSpec)
      END DO
    END IF

#if (PP_TimeDiscMethod==1000)
    IF (CollisMode.GT.1) THEN
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') IntEn(iSpec,1)
      END DO
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') IntEn(iSpec,2)
      END DO
      IF ( DSMC%ElectronicModel ) THEN
        DO iSpec=1, nSpecies
        ! currently set to one
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') IntEn(iSpec,3)
        END DO
      END IF
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') IntTemp(iSpec,1)
      END DO
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') IntTemp(iSpec,2)
      END DO
    END IF
#endif

#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || PP_TimeDiscMethod==300 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
    IF (CollisMode.GT.1) THEN
      IF(CalcEint) THEN
        DO iSpec=1, nSpecies
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') IntEn(iSpec,1)
        END DO
        DO iSpec=1, nSpecies
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') IntEn(iSpec,2)
        END DO
        IF (DSMC%ElectronicModel) THEN
          DO iSpec=1, nSpecies
          ! currently set to one
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,104,ADVANCE='NO') IntEn(iSpec,3)
          END DO
        END IF
      END IF
      IF(CalcTemp) THEN
        DO iSpec=1, nSpecies
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') IntTemp(iSpec,1)
        END DO
        DO iSpec=1, nSpecies
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') Xi_Vib(iSpec)
        END DO
        DO iSpec=1, nSpecies
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') IntTemp(iSpec,2)
        END DO
        DO iSpec=1, nSpecies+1
          WRITE(unit_index,'(A1)',ADVANCE='NO') ','
          WRITE(unit_index,104,ADVANCE='NO') TempTotal(iSpec)
        END DO
        IF ( DSMC%ElectronicModel ) THEN
          DO iSpec=1, nSpecies
          ! currently set to one
            WRITE(unit_index,'(A1)',ADVANCE='NO') ','
            WRITE(unit_index,104,ADVANCE='NO') IntTemp(iSpec,3)
          END DO
        END IF
      END IF
    END IF
#if (PP_TimeDiscMethod==2 || PP_TimeDiscMethod==4 || PP_TimeDiscMethod==42 || (PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506))
    IF(DSMC%CalcQualityFactors) THEN
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') MeanCollProb
      WRITE(unit_index,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index,104,ADVANCE='NO') MaxCollProb
    END IF
#endif
#if (PP_TimeDiscMethod==42)
! output for adsorption
    IF (DSMC%WallModel.GE.1) THEN
!         IF (CalcWallNumSpec) THEN
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,'(I18.1)',ADVANCE='NO') WallNumSpec(iSpec)
      END DO
!         END IF
!         IF (CalcWallCoverage) THEN
      DO iSpec=1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') WallCoverage(iSpec)
      END DO
!         END IF 
      DO iSpec = 1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') Adsorptionrate(iSpec)
      END DO
      DO iSpec = 1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') Desorptionrate(iSpec)
      END DO
      DO iSpec = 1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,'(I18.1)',ADVANCE='NO') Adsorption%AdsorpInfo(iSpec)%NumOfAds
      END DO
      DO iSpec = 1, nSpecies
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,'(I18.1)',ADVANCE='NO') Adsorption%AdsorpInfo(iSpec)%NumOfDes
      END DO
      IF (Adsorption%TPD) THEN
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') Adsorption%TPD_Temp
      END IF
    END IF
    IF(CalcCollRates) THEN
      DO iCase=1, CollInf%NumCase +1 
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') CRate(iCase)
      END DO
    END IF
    IF(CalcReacRates) THEN
      DO iCase=1, ChemReac%NumOfReact 
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,104,ADVANCE='NO') RRate(iCase)
      END DO
    END IF
#endif /*(PP_TimeDiscMethod==42)*/
#endif
    WRITE(unit_index,'(A1)') ' ' 
#ifdef MPI
  END IF
#endif    /* MPI */

    104    FORMAT (e25.14)

!SWRITE(UNIT_stdOut,'(A)')' PARTCILE ANALYZE DONE!'
!SWRITE(UNIT_StdOut,'(132("-"))')
ELSE
!SWRITE(UNIT_stdOut,'(A)')' NO PARTCILE ANALYZE TO DO!'
!SWRITE(UNIT_StdOut,'(132("-"))')
  END IF ! DoAnalyze
!-----------------------------------------------------------------------------------------------------------------------------------
  IF( CalcPartBalance) CALL CalcParticleBalance()
!-----------------------------------------------------------------------------------------------------------------------------------
#ifdef MPI 
tLBEnd = LOCALTIME() ! LB Time End
tCurrent(14)=tCurrent(14)+tLBEnd-tLBStart
#endif /*MPI*/

#if ( PP_TimeDiscMethod ==42 )
! hard coded
! array not allocated
  IF ( DSMC%ElectronicModel ) THEN
  IF (DSMC%ReservoirSimuRate) THEN
    IF(Time.GT.0.) CALL ElectronicTransition( Time, NumSpec )
  END IF
END IF
#endif
!-----------------------------------------------------------------------------------------------------------------------------------
#if ( PP_TimeDiscMethod ==42 )
  ! Debug Output for initialized electronic state
  IF ( DSMC%ElectronicModel .AND. DSMC%ReservoirSimuRate) THEN
    DO iSpec = 1, nSpecies
      IF ( SpecDSMC(iSpec)%InterID .ne. 4 ) THEN
        IF (  SpecDSMC(iSpec)%levelcounter(0) .ne. 0) THEN
          WRITE(DebugElectronicStateFilename,'(I2.2)') iSpec
          iunit = 485
          DebugElectronicStateFilename = 'End_Electronic_State_Species_'//trim(DebugElectronicStateFilename)//'.dat'
          OPEN(unit=iunit,file=DebugElectronicStateFilename,form='formatted',status='unknown')
          DO ii = 0, SpecDSMC(iSpec)%MaxElecQuant - 1                         !has to be changed when using %Init definitions!!!
            WRITE(iunit,'(I3.1,3x,F12.7)') ii, REAL( SpecDSMC(iSpec)%levelcounter(ii) ) / &
                                               REAL( Species(iSpec)%Init(0)%initialParticleNumber)
          END DO
          CLOSE(iunit)
        END IF
      END IF
    END DO
  END IF
#endif
!-----------------------------------------------------------------------------------------------------------------------------------
END SUBROUTINE AnalyzeParticles

! all other analysis with particles
SUBROUTINE CalcShapeEfficiencyR()
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Particle_Analyze_Vars,   ONLY : CalcShapeEfficiencyMethod, ShapeEfficiencyNumber
USE MOD_Mesh_Vars,               ONLY : nElems, Elem_xGP
USE MOD_Particle_Mesh_Vars,      ONLY : GEO
USE MOD_PICDepo_Vars
USE MOD_Particle_Vars
USE MOD_PreProc
#ifdef MPI
USE MOD_Particle_MPI_Vars,       ONLY : PartMPI
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                     :: NbrOfComps, NbrWithinRadius, NbrOfElems, NbrOfElemsWithinRadius
REAL                     :: RandVal1
LOGICAL                  :: chargedone(1:nElems), WITHIN
INTEGER                  :: kmin, kmax, lmin, lmax, mmin, mmax                           !
INTEGER                  :: kk, ll, mm, ppp,m,l,k, i                                             !
INTEGER                  :: ElemID
REAL                     :: radius, deltax, deltay, deltaz
!===================================================================================================================================

NbrOfComps = 0.
NbrOfElems = 0.
NbrWithinRadius = 0.
NbrOfElemsWithinRadius = 0.
SELECT CASE(CalcShapeEfficiencyMethod)
CASE('AllParts')
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
      chargedone(:) = .FALSE.
      !-- determine which background mesh cells (and interpolation points within) need to be considered
      kmax = INT((PartState(i,1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
      kmax = MIN(kmax,GEO%FIBGMimax)
      kmin = INT((PartState(i,1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
      kmin = MAX(kmin,GEO%FIBGMimin)
      lmax = INT((PartState(i,2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
      lmax = MIN(lmax,GEO%FIBGMjmax)
      lmin = INT((PartState(i,2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
      lmin = MAX(lmin,GEO%FIBGMjmin)
      mmax = INT((PartState(i,3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
      mmax = MIN(mmax,GEO%FIBGMkmax)
      mmin = INT((PartState(i,3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
      mmin = MAX(mmin,GEO%FIBGMkmin)
      !-- go through all these cells
      DO kk = kmin,kmax
        DO ll = lmin, lmax
          DO mm = mmin, mmax
            !--- go through all mapped elements not done yet
            DO ppp = 1,GEO%FIBGM(kk,ll,mm)%nElem
              WITHIN=.FALSE.
              ElemID = GEO%FIBGM(kk,ll,mm)%Element(ppp)
              IF (.NOT.chargedone(ElemID)) THEN
                NbrOfElems = NbrOfElems + 1.
                !--- go through all gauss points
                DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
                  NbrOfComps = NbrOfComps + 1.
                  !-- calculate distance between gauss and particle
                  deltax = PartState(i,1) - Elem_xGP(1,k,l,m,ElemID)
                  deltay = PartState(i,2) - Elem_xGP(2,k,l,m,ElemID)
                  deltaz = PartState(i,3) - Elem_xGP(3,k,l,m,ElemID)
                  radius = deltax * deltax + deltay * deltay + deltaz * deltaz
                  IF (radius .LT. r2_sf) THEN
                    WITHIN=.TRUE.
                    NbrWithinRadius = NbrWithinRadius + 1.
                  END IF
                END DO; END DO; END DO
                chargedone(ElemID) = .TRUE.
              END IF
              IF(WITHIN) NbrOfElemsWithinRadius = NbrOfElemsWithinRadius + 1.
            END DO ! ppp
          END DO ! mm
        END DO ! ll
      END DO ! kk
    END IF ! inside
  END DO ! i
IF(NbrOfComps.GT.0.0)THEN
#ifdef MPI
  WRITE(*,*) 'ShapeEfficiency (Proc,%,%Elems)',PartMPI%MyRank,100*NbrWithinRadius/NbrOfComps,100*NbrOfElemsWithinRadius/NbrOfElems
  WRITE(*,*) 'ShapeEfficiency (Elems) for Proc',PartMPI%MyRank,'is',100*NbrOfElemsWithinRadius/NbrOfElems,'%'
#else
  WRITE(*,*) 'ShapeEfficiency (%,%Elems)',100*NbrWithinRadius/NbrOfComps, 100*NbrOfElemsWithinRadius/NbrOfElems
  WRITE(*,*) 'ShapeEfficiency (Elems) is',100*NbrOfElemsWithinRadius/NbrOfElems,'%'
#endif
END IF
CASE('SomeParts')
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
      CALL RANDOM_NUMBER(RandVal1)
      IF(RandVal1.LT.REAL(ShapeEfficiencyNumber)/100)THEN
        chargedone(:) = .FALSE.
        !-- determine which background mesh cells (and interpolation points within) need to be considered
        kmax = INT((PartState(i,1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
        kmax = MIN(kmax,GEO%FIBGMimax)
        kmin = INT((PartState(i,1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
        kmin = MAX(kmin,GEO%FIBGMimin)
        lmax = INT((PartState(i,2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
        lmax = MIN(lmax,GEO%FIBGMjmax)
        lmin = INT((PartState(i,2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
        lmin = MAX(lmin,GEO%FIBGMjmin)
        mmax = INT((PartState(i,3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
        mmax = MIN(mmax,GEO%FIBGMkmax)
        mmin = INT((PartState(i,3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
        mmin = MAX(mmin,GEO%FIBGMkmin)
        !-- go through all these cells
        DO kk = kmin,kmax
          DO ll = lmin, lmax
            DO mm = mmin, mmax
              !--- go through all mapped elements not done yet
              DO ppp = 1,GEO%FIBGM(kk,ll,mm)%nElem
              WITHIN=.FALSE.
                ElemID = GEO%FIBGM(kk,ll,mm)%Element(ppp)
                IF (.NOT.chargedone(ElemID)) THEN
                  NbrOfElems = NbrOfElems + 1
                  !--- go through all gauss points
                  DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
                    NbrOfComps = NbrOfComps + 1
                    !-- calculate distance between gauss and particle
                    deltax = PartState(i,1) - Elem_xGP(1,k,l,m,ElemID)
                    deltay = PartState(i,2) - Elem_xGP(2,k,l,m,ElemID)
                    deltaz = PartState(i,3) - Elem_xGP(3,k,l,m,ElemID)
                    radius = deltax * deltax + deltay * deltay + deltaz * deltaz
                    IF (radius .LT. r2_sf) THEN
                      NbrWithinRadius = NbrWithinRadius + 1
                      WITHIN=.TRUE.
                    END IF
                    END DO; END DO; END DO
                    chargedone(ElemID) = .TRUE.
                  END IF
                  IF(WITHIN) NbrOfElemsWithinRadius = NbrOfElemsWithinRadius + 1
                END DO ! ppp
              END DO ! mm
            END DO ! ll
          END DO ! kk
        END IF  ! RandVal
      END IF ! inside
  END DO ! i
IF(NbrOfComps.GT.0)THEN
#ifdef MPI
  WRITE(*,*) 'ShapeEfficiency (Proc,%,%Elems)',PartMPI%MyRank,100*NbrWithinRadius/NbrOfComps,100*NbrOfElemsWithinRadius/NbrOfElems
  WRITE(*,*) 'ShapeEfficiency (Elems) for Proc',PartMPI%MyRank,'is',100*NbrOfElemsWithinRadius/NbrOfElems,'%'
#else
  WRITE(*,*) 'ShapeEfficiency (%,%Elems)',100*NbrWithinRadius/NbrOfComps,100*NbrOfElemsWithinRadius/NbrOfElems
  WRITE(*,*) 'ShapeEfficiency (Elems) is',100*NbrOfElemsWithinRadius/NbrOfElems,'%'
#endif
END IF
END SELECT
END SUBROUTINE CalcShapeEfficiencyR


#if (PP_TimeDiscMethod==42)
SUBROUTINE GetWallNumSpec(WallNumSpec,WallCoverage)
!===================================================================================================================================
! Calculate number of wallparticles for all species
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_Vars,      ONLY : Species, PartSpecies, PDM, nSpecies, KeepWallParticles
USE MOD_DSMC_Vars,          ONLY : Adsorption
USE MOD_Particle_Boundary_Vars, ONLY : nSurfSample, SurfMesh
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER, INTENT(OUT)            :: WallNumSpec(nSpecies)
REAL   , INTENT(OUT)            :: WallCoverage(nSpecies)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: i, iSurfSide, p, q
REAL              :: Surface, Coverage(nSpecies), SurfPartDens
!===================================================================================================================================
  WallNumSpec = 0
  SurfPartDens = 0
  Surface = 0.
  Coverage(:) = 0.
  DO i=1,nSpecies
  DO iSurfSide=1,SurfMesh%nSides
    DO q = 1,nSurfSample
      DO p = 1,nSurfSample
        Surface = Surface + SurfMesh%SurfaceArea(p,q,iSurfSide)
        Coverage(i) = Coverage(i) + Adsorption%Coverage(p,q,iSurfSide,i)
      END DO
    END DO
    SurfPartDens = SurfPartDens + Adsorption%DensSurfAtoms(iSurfSide)/Species(i)%MacroParticleFactor
  END DO
  END DO
  WallCoverage(:) = Coverage(:) / (SurfMesh%nSides*nSurfSample*nSurfSample)
  
  IF (KeepWallParticles) THEN
    DO i=1,PDM%ParticleVecLength
      IF (PDM%ParticleInside(i) .AND. PDM%ParticleAtWall(i)) THEN
        WallNumSpec(PartSpecies(i)) = WallNumSpec(PartSpecies(i)) + 1
      END IF
    END DO
  ELSE 
    DO i=1,nSpecies
      WallNumSpec(i) = INT(WallCoverage(i) * Surface * SurfPartDens)
      IF (WallNumSpec(i).EQ.0) THEN
       WallCoverage(i) = 0.
      END IF
    END DO
  END IF
    
END SUBROUTINE GetWallNumSpec

SUBROUTINE CalcSurfRates(WallNumSpec,Adsorbrate,Desorbrate)
!===================================================================================================================================
! Calculate number of wallparticles for all species
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_Vars,      ONLY : nSpecies
USE MOD_DSMC_Vars,          ONLY : Adsorption, DSMC
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER, INTENT(IN)             :: WallNumSpec(nSpecies)
REAL   , INTENT(OUT)            :: Adsorbrate(nSpecies), Desorbrate(nSpecies)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iSpec
!===================================================================================================================================

IF (DSMC%ReservoirRateStatistic) THEN
  DO iSpec = 1,nSpecies
    Adsorbrate(iSpec) = Adsorption%AdsorpInfo(iSpec)%NumOfAds / Adsorption%AdsorpInfo(iSpec)%WallCollCount
    Desorbrate(iSpec) = Adsorption%AdsorpInfo(iSpec)%NumOfDes / WallNumSpec(iSpec)
  END DO
ELSE
  DO iSpec = 1,nSpecies
    Adsorbrate(iSpec) = Adsorption%AdsorpInfo(iSpec)%MeanProbAds
    Desorbrate(iSpec) = Adsorption%AdsorpInfo(iSpec)%MeanProbDes
  END DO
END IF

END SUBROUTINE CalcSurfRates
#endif

SUBROUTINE CalcParticleBalance()
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_Analyze_Vars,      ONLY : nPartIn,nPartOut,PartEkinIn,PartEkinOut
#if defined(LSERK) || defined(IMEX) || defined(IMPA)
!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
USE MOD_Particle_Analyze_Vars,      ONLY : nPartInTmp,PartEkinInTmp
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

#if defined(LSERK) || defined(IMEX) || defined(IMPA)
!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
nPartIn=nPartInTmp
nPartOut=0
PartEkinIn=PartEkinInTmp
PartEkinOut=0.
nPartInTmp=0
PartEkinInTmp=0.
#else
nPartIn=0
nPartOut=0
PartEkinIn=0.
PartEkinOut=0.
#endif

END SUBROUTINE CalcParticleBalance

SUBROUTINE CalcKineticEnergy(Ekin) 
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Equation_Vars,          ONLY : c2, c2_inv
USE MOD_Particle_Vars,          ONLY : PartState, PartSpecies, Species, PDM
USE MOD_PARTICLE_Vars,          ONLY : nSpecies, PartMPF, usevMPF
USE MOD_Particle_Analyze_Vars,  ONLY : nEkin
#ifndef PP_HDG
USE MOD_PML_Vars,               ONLY : DoPML,xyzPhysicalMinMax
#endif /*PP_HDG*/ 
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: Ekin(nEkin) 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: i
REAL(KIND=8)              :: partV2, Gamma
!===================================================================================================================================

Ekin = 0.!d0
IF (nEkin .GT. 1 ) THEN
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
#ifndef PP_HDG
      IF(DoPML)THEN
        IF (PartState(i,1) .GE. xyzPhysicalMinMax(1) .AND. PartState(i,1) .LE. xyzPhysicalMinMax(2) .AND. &
            PartState(i,2) .GE. xyzPhysicalMinMax(3) .AND. PartState(i,2) .LE. xyzPhysicalMinMax(4) .AND. &
            PartState(i,3) .GE. xyzPhysicalMinMax(5) .AND. PartState(i,3) .LE. xyzPhysicalMinMax(6)) THEN        
          CYCLE
        END IF
      ENDIF
#endif /*PP_HDG*/ 
      partV2 = PartState(i,4) * PartState(i,4) &
              + PartState(i,5) * PartState(i,5) &
              + PartState(i,6) * PartState(i,6)
      IF ( partV2 .LT. 1e6) THEN  ! |v| < 1000
  !       Ekin = Ekin + 0.5 *  Species(PartSpecies(i))%MassIC * partV2 * PartMPF(i)            
        IF(usevMPF) THEN
          Ekin(nSpecies+1)     = Ekin(nSpecies+1)     + 0.5 * Species(PartSpecies(i))%MassIC * partV2 * PartMPF(i)
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + 0.5 * Species(PartSpecies(i))%MassIC * partV2 * PartMPF(i)
        ELSE
          Ekin(nSpecies+1) = Ekin(nSpecies+1) + 0.5 *  Species(PartSpecies(i))%MassIC * partV2 &
                                            *  Species(PartSpecies(i))%MacroParticleFactor
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + 0.5 *  Species(PartSpecies(i))%MassIC * partV2 &
                                            *  Species(PartSpecies(i))%MacroParticleFactor
        END IF != usevMPF
      ELSE ! partV2 > 1e6
  !       Ekin = Ekin + (gamma - 1) * mass * MPF *c^2
        Gamma = partV2*c2_inv
        Gamma = 1./SQRT(1.-Gamma)
        IF(usevMPF) THEN
          Ekin(nSpecies+1)     = Ekin(nSpecies+1)     + PartMPF(i) * (Gamma-1.) * Species(PartSpecies(i))%MassIC * c2
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + PartMPF(i) * (Gamma-1.) * Species(PartSpecies(i))%MassIC * c2
        ELSE
          Ekin(nSpecies+1)     = Ekin(nSpecies+1)     + (Gamma-1.) * Species(PartSpecies(i))%MassIC &
                                                                   * Species(PartSpecies(i))%MacroParticleFactor * c2
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + (Gamma-1.) * Species(PartSpecies(i))%MassIC &
                                                                   * Species(PartSpecies(i))%MacroParticleFactor * c2
        END IF !=usevMPF
      END IF ! partV2
    END IF ! (PDM%ParticleInside(i))
  END DO ! i=1,PDM%ParticleVecLength
ELSE ! nEkin = 1 : only 1 species
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
#ifndef PP_HDG
      IF(DoPML)THEN
        IF (PartState(i,1) .GE. xyzPhysicalMinMax(1) .AND. PartState(i,1) .LE. xyzPhysicalMinMax(2) .AND. &
            PartState(i,2) .GE. xyzPhysicalMinMax(3) .AND. PartState(i,2) .LE. xyzPhysicalMinMax(4) .AND. &
            PartState(i,3) .GE. xyzPhysicalMinMax(5) .AND. PartState(i,3) .LE. xyzPhysicalMinMax(6)) THEN        
          CYCLE
        END IF
      ENDIF
#endif /*PP_HDG*/ 
      partV2 = PartState(i,4) * PartState(i,4) &
             + PartState(i,5) * PartState(i,5) &
             + PartState(i,6) * PartState(i,6)
      IF ( partV2 .LT. 1e6) THEN  ! |v| < 1000
        IF(usevMPF) THEN
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + 0.5 *  Species(PartSpecies(i))%MassIC * partV2 &
                                            * PartMPF(i)            
        ELSE
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + 0.5 *  Species(PartSpecies(i))%MassIC * partV2 &
                                            *  Species(PartSpecies(i))%MacroParticleFactor
        END IF ! usevMPF
      ELSE ! partV2 > 1e6
        Gamma = partV2*c2_inv
        Gamma = 1./SQRT(1.-Gamma)
        IF(usevMPF)THEN
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + PartMPF(i) * (Gamma-1.) &
                      * Species(PartSpecies(i))%MassIC * c2
        ELSE
          Ekin(PartSpecies(i)) = Ekin(PartSpecies(i)) + (Gamma -1.) &
                      * Species(PartSpecies(i))%MassIC &
                      * Species(PartSpecies(i))%MacroParticleFactor * c2
        END IF ! useuvMPF

      END IF ! par2
    END IF ! particle inside
  END DO ! particleveclength
END IF

END SUBROUTINE CalcKineticEnergy


SUBROUTINE CalcTemperature(Temp, NumSpec)
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_Vars,      ONLY : PartState, PartSpecies, Species, PDM, nSpecies, BoltzmannConst, PartMPF, usevMPF
#if (PP_TimeDiscMethod==1000)
USE MOD_LD_Vars,            ONLY : BulkValues
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                :: NumSpec(:)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: Temp(:)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: i, iSpec
REAL              ::  TempDirec(nSpecies,3)
#if (PP_TimeDiscMethod!=1000)
REAL              :: PartV(nSpecies, 3), PartV2(nSpecies,3),Mean_PartV2(nSpecies, 3), MeanPartV_2(nSpecies,3)
#endif
!===================================================================================================================================

! Compute velocity averages
  Temp = 0.0
! Sum up velocity
#if (PP_TimeDiscMethod==1000)
  DO iSpec=1, nSpecies
    TempDirec(iSpec,1:3) = BulkValues(1)%BulkTemperature
    Temp(iSpec) = BulkValues(1)%BulkTemperature
  END DO
#else 
  PartV = 0
  PartV2 = 0
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
      IF (usevMPF) THEN 
        PartV(PartSpecies(i),1:3) = PartV(PartSpecies(i),1:3) + PartState(i,4:6) * PartMPF(i)
        PartV2(PartSpecies(i),1:3) = PartV2(PartSpecies(i),1:3) + PartState(i,4:6)**2 * PartMPF(i)
      ELSE
        PartV(PartSpecies(i),1:3) = PartV(PartSpecies(i),1:3) + PartState(i,4:6)
        PartV2(PartSpecies(i),1:3) = PartV2(PartSpecies(i),1:3) + PartState(i,4:6)**2
      END IF
    END IF
  END DO
  DO iSpec=1, nSpecies
    IF(NumSpec(iSpec).NE.0) THEN
      ! Compute velocity averages
      MeanPartV_2(iSpec,1:3)  = (PartV(iSpec,1:3) / NumSpec(iSpec))**2       ! < |v| >**2
      Mean_PartV2(iSpec,1:3)  = PartV2(iSpec,1:3) / NumSpec(iSpec)           ! < |v|**2 >
    ELSE
      MeanPartV_2(iSpec,1:3) = 0.
      Mean_PartV2(iSpec,1:3) = 0.
    END IF
    ! Compute temperatures
    TempDirec(iSpec,1:3) = Species(iSpec)%MassIC * (Mean_PartV2(iSpec,1:3) - MeanPartV_2(iSpec,1:3)) &
         / BoltzmannConst ! Temp calculation is limitedt to one species
    Temp(iSpec) = (TempDirec(iSpec,1) + TempDirec(iSpec,2) + TempDirec(iSpec,3))/3
    Temp(nSpecies + 1) = Temp(nSpecies + 1) + Temp(iSpec)*NumSpec(iSpec)
  END DO
  Temp(nSpecies+1) = Temp(nSpecies + 1) / NumSpec(nSpecies+1)
#endif
END SUBROUTINE CalcTemperature

SUBROUTINE CalcVelocities(PartVtrans, PartVtherm)
!===================================================================================================================================
! Calculates the drift and eigen velocity of all particles: PartVtotal = PartVtrans + PartVtherm 
! PartVtrans(nSpecies,4) ! macroscopic velocity (drift velocity) A. Frohn: kinetische Gastheorie
! PartVtherm(nSpecies,4) ! microscopic velocity (eigen velocity)
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Analyze_Vars, ONLY : VeloDirs
USE MOD_Particle_Vars,         ONLY : PartState, PartSpecies, PDM, nSpecies, PartMPF, usevMPF
! IMPLICIT VARIABLE HANDLING
#ifdef MPI
USE MOD_Particle_MPI_Vars,    ONLY: PartMPI
#endif
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: PartVtrans(:,:), PartVtherm(:,:) 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iSpec
INTEGER                        :: i
INTEGER                        :: NumSpecloc(nSpecies)
INTEGER                        :: NumSpecglob(nSpecies)
INTEGER                        :: dir
REAL                           :: RealNumSpecloc(nSpecies), RealNumSpecglob(nSpecies)
REAL                           :: PartVglob(nSpecies,4), PartVthermglob(nSpecies,4)
!===================================================================================================================================
! Compute velocity averages
  PartVtrans = 0.
  PartVglob = 0.
  PartVthermglob = 0.
  PartVtherm = 0.
  NumSpecloc = 0
  NumSpecglob = 0
  RealNumSpecloc = 0.
  RealNumSpecglob = 0.

  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
      IF (usevMPF) THEN
        RealNumSpecloc(PartSpecies(i)) = RealNumSpecloc(PartSpecies(i)) + PartMPF(i)
      END IF
      NumSpecloc(PartSpecies(i)) = NumSpecloc(PartSpecies(i)) + 1
      DO dir = 1,3
        IF (VeloDirs(dir) .OR. VeloDirs(4)) THEN
          IF (usevMPF) THEN 
            PartVtrans(PartSpecies(i),dir) = PartVtrans(PartSpecies(i),dir) + PartState(i,dir+3) * PartMPF(i)
          ELSE
            PartVtrans(PartSpecies(i),dir) = PartVtrans(PartSpecies(i),dir) + PartState(i,dir+3)
          END IF
        END IF
      END DO
    END IF
  END DO
#ifdef MPI
  CALL MPI_ALLREDUCE(PartVtrans, PartVglob, 4*nSpecies, MPI_DOUBLE_PRECISION, MPI_SUM,  PartMPI%COMM, IERROR)
  PartVtrans = PartVglob
#endif
  IF (usevMPF) THEN
#ifdef MPI
    CALL MPI_ALLREDUCE(RealNumSpecloc, RealNumSpecglob, nSpecies, MPI_DOUBLE_PRECISION, MPI_SUM,  PartMPI%COMM, IERROR)
    RealNumSpecloc = RealNumSpecglob
#endif
    DO dir = 1,3
      IF (VeloDirs(dir) .OR. VeloDirs(4)) THEN
        DO iSpec = 1,nSpecies
          IF(RealNumSpecloc(iSpec).EQ.0)THEN
            PartVtrans(iSpec,dir) = 0.
          ELSE
            PartVtrans(iSpec,dir) = PartVtrans(iSpec,dir)/RealNumSpecloc(iSpec)
          END IF
        END DO ! iSpec = 1,nSpecies
      END IF
    END DO
  ELSE !no vMPF
#ifdef MPI
    CALL MPI_ALLREDUCE(NumSpecloc, NumSpecglob, nSpecies, MPI_INTEGER, MPI_SUM, PartMPI%COMM, IERROR)
    NumSpecloc = NumSpecglob
#endif
    DO dir = 1,3
      IF (VeloDirs(dir) .OR. VeloDirs(4)) THEN
        DO iSpec = 1,nSpecies
          IF(NumSpecloc(iSpec).EQ.0)THEN
            PartVtrans(iSpec,dir) = 0.
          ELSE
            PartVtrans(iSpec,dir) = PartVtrans(iSpec,dir)/NumSpecloc(iSpec)
          END IF
        END DO ! iSpec = 1,nSpecies
      END IF
    END DO
  END IF !usevMPF
  
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
      DO dir = 1,3
        IF (VeloDirs(dir) .OR. VeloDirs(4)) THEN
          IF (usevMPF) THEN 
            PartVtherm(PartSpecies(i),dir) = PartVtherm(PartSpecies(i),dir) + PartMPF(i) * &
                (PartState(i,dir+3) - PartVtrans(PartSpecies(i),dir))*(PartState(i,dir+3) - PartVtrans(PartSpecies(i),dir))
          ELSE
            PartVtherm(PartSpecies(i),dir) = PartVtherm(PartSpecies(i),dir) + &
                (PartState(i,dir+3) - PartVtrans(PartSpecies(i),dir))*(PartState(i,dir+3) - PartVtrans(PartSpecies(i),dir))
          END IF
        END IF
      END DO
    END IF
  END DO
#ifdef MPI
  CALL MPI_ALLREDUCE(PartVtherm, PartVthermglob, 4*nSpecies, MPI_DOUBLE_PRECISION, MPI_SUM,  PartMPI%COMM, IERROR)
  PartVtherm = PartVthermglob
#endif
  DO dir = 1,3
    IF (VeloDirs(dir) .OR. VeloDirs(4)) THEN
      DO iSpec = 1,nSpecies
        IF (usevMPF) THEN
          IF(RealNumSpecloc(iSpec).EQ.0)THEN
            PartVtherm(iSpec,dir)=0.
          ELSE
            PartVtherm(iSpec,dir)=PartVtherm(iSpec,dir)/RealNumSpecloc(iSpec)
          END IF
        ELSE
          IF(NumSpecloc(iSpec).EQ.0)THEN
            PartVtherm(iSpec,dir)=0.
          ELSE
            PartVtherm(iSpec,dir)=PartVtherm(iSpec,dir)/NumSpecloc(iSpec)
          END IF
        END IF
      END DO ! iSpec = 1,nSpecies
    END IF
  END DO
 ! calc abolute value
  IF (VeloDirs(4)) THEN
    PartVtrans(:,4) = SQRT(PartVtrans(:,1)*PartVtrans(:,1) + PartVtrans(:,2)*PartVtrans(:,2) + PartVtrans(:,3)*PartVtrans(:,3))
    PartVtherm(:,4) = PartVtherm(:,1) + PartVtherm(:,2) + PartVtherm(:,3)
  END IF
  PartVtherm(:,:) = SQRT(PartVtherm(:,:))
END SUBROUTINE CalcVelocities


SUBROUTINE CalcIntTempsAndEn(IntTemp, IntEn)
!===================================================================================================================================
! Calculation of internal Temps (TVib, TRot)
!===================================================================================================================================
! MODULES
USE MOD_Particle_Vars,      ONLY : PartSpecies, Species, PDM, nSpecies, BoltzmannConst, PartMPF, usevMPF
USE MOD_DSMC_Vars,          ONLY : PartStateIntEn, SpecDSMC, DSMC, PolyatomMolDSMC
USE MOD_DSMC_Analyze,       ONLY : CalcTVib, CalcTelec, CalcTVibPoly
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: IntTemp(:,:) , IntEn(:,:) 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iPart, iSpec
INTEGER           :: NumSpec(nSpecies)
REAL              :: EVib(nSpecies), ERot(nSpecies), Eelec(nSpecies), RealNumSpec(nSpecies), tempVib, NumSpecTemp
!REAL              :: CalcTVib
!===================================================================================================================================
NumSpec = 0
EVib    = 0.
ERot    = 0.
Eelec   = 0.
! set electronic state to zero
IntTemp(:,3) = 0.
RealNumSpec  = 0.

! Sum up internal energies
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
      IF (usevMPF) THEN
        EVib(PartSpecies(iPart)) = EVib(PartSpecies(iPart)) + PartStateIntEn(iPart,1) * PartMPF(iPart)
        ERot(PartSpecies(iPart)) = ERot(PartSpecies(iPart)) + PartStateIntEn(iPart,2) * PartMPF(iPart)
        NumSpec(PartSpecies(iPart)) = NumSpec(PartSpecies(iPart)) + 1
        RealNumSpec(PartSpecies(iPart)) = RealNumSpec(PartSpecies(iPart)) + PartMPF(iPart)
        IF ( DSMC%ElectronicModel ) THEN
          Eelec(PartSpecies(iPart)) = Eelec(PartSpecies(iPart)) + PartStateIntEn(iPart,3) * PartMPF(iPart)
        END IF
      ELSE
        EVib(PartSpecies(iPart)) = EVib(PartSpecies(iPart)) + PartStateIntEn(iPart,1)
        ERot(PartSpecies(iPart)) = ERot(PartSpecies(iPart)) + PartStateIntEn(iPart,2)
        IF ( DSMC%ElectronicModel ) THEN
          Eelec(PartSpecies(iPart)) = Eelec(PartSpecies(iPart)) + PartStateIntEn(iPart,3)
        END IF
       NumSpec(PartSpecies(iPart)) = NumSpec(PartSpecies(iPart)) + 1
      END IF
    END IF
  END DO
! Calc TVib, TRot
  DO iSpec = 1, nSpecies
    IF (usevMPF) THEN
      NumSpecTemp = RealNumSpec(iSpec)
    ELSE
      NumSpecTemp = REAL(NumSpec(iSpec))
    END IF
    IF(((SpecDSMC(iSpec)%InterID.EQ.2).OR.(SpecDSMC(iSpec)%InterID.EQ.20)).AND.(NumSpecTemp.GT.0.0)) THEN
      IF (SpecDSMC(iSpec)%PolyatomicMol.AND.(SpecDSMC(iSpec)%Xi_Rot.EQ.3)) THEN 
        IntTemp(iSpec,2) = 2.0*ERot(iSpec)/(3.0*BoltzmannConst*NumSpecTemp)  !Calc TRot          
      ELSE
        IntTemp(iSpec,2) = ERot(iSpec)/(BoltzmannConst*NumSpecTemp)  !Calc TRot
      END IF
      IF (EVib(iSpec)/NumSpecTemp.GT.SpecDSMC(iSpec)%EZeroPoint) THEN
        IF (SpecDSMC(iSpec)%PolyatomicMol) THEN
          IntTemp(iSpec,1) = CalcTVibPoly(EVib(iSpec)/NumSpecTemp, iSpec)
        ELSE
          IF (DSMC%VibEnergyModel.EQ.0) THEN              ! SHO-model
            tempVib = (EVib(iSpec)/(NumSpecTemp*BoltzmannConst*SpecDSMC(iSpec)%CharaTVib)-DSMC%GammaQuant)
            IF ((tempVib.GT.0.0) &
              .OR.(EVib(iSpec)/(NumSpecTemp*BoltzmannConst*SpecDSMC(iSpec)%CharaTVib).LE.DSMC%GammaQuant)) THEN
              IntTemp(iSpec,1) = SpecDSMC(iSpec)%CharaTVib/LOG(1 + 1/(EVib(iSpec) & 
                                /(NumSpecTemp*BoltzmannConst*SpecDSMC(iSpec)%CharaTVib)-DSMC%GammaQuant))
            END IF
          ELSE                                            ! TSHO-model
            IntTemp(iSpec,1) = CalcTVib(SpecDSMC(iSpec)%CharaTVib, EVib(iSpec)/NumSpecTemp, SpecDSMC(iSpec)%MaxVibQuant)
          END IF
        END IF
      ELSE
        IntTemp(iSpec,1) = 0
      END IF
    ELSE
      IntTemp(iSpec,1) = 0
      IntTemp(iSpec,2) = 0
    END IF
    IF ( DSMC%ElectronicModel ) THEN
      IF ((NumSpecTemp.GT.0).AND.(SpecDSMC(iSpec)%InterID.NE.4) ) THEN
        IntTemp(iSpec,3) = CalcTelec(Eelec(iSpec)/NumSpecTemp,iSpec)
        IntEn(iSpec,3) = Eelec(iSpec)
      ELSE
        IntEn(iSpec,3) = 0.0
      END IF
    END IF
    IntEn(iSpec,1) = EVib(iSpec)
    IntEn(iSpec,2) = ERot(iSpec)
    IF(.NOT.usevMPF) IntEn(iSpec,:) = IntEn(iSpec,:) * Species(iSpec)%MacroParticleFactor
  END DO

END SUBROUTINE CalcIntTempsAndEn

#if (PP_TimeDiscMethod==42)
SUBROUTINE CollRates(CRate) 
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_DSMC_Vars,          ONLY: CollInf, DSMC
USE MOD_TimeDisc_Vars,      ONLY: dt
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: CRate(:) 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iCase
!===================================================================================================================================

  DO iCase=1, CollInf%NumCase + 1
    CRate(iCase) =  DSMC%NumColl(iCase) / dt
  END DO
  DSMC%NumColl = 0
END SUBROUTINE CollRates

SUBROUTINE ReacRates(RRate, NumSpec) 
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_DSMC_Vars,          ONLY: ChemReac, DSMC
USE MOD_TimeDisc_Vars,      ONLY: dt
USE MOD_Particle_Vars,      ONLY: Species, nSpecies
USE MOD_Particle_Mesh_Vars, ONLY: GEO
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: RRate(:) 
REAL,INTENT(IN)                 :: NumSpec(:)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: iReac
!===================================================================================================================================

  DO iReac=1, ChemReac%NumOfReact
    IF ((NumSpec(ChemReac%DefinedReact(iReac,1,1)).GT.0).AND.(NumSpec(ChemReac%DefinedReact(iReac,1,2)).GT.0)) THEN
      SELECT CASE(TRIM(ChemReac%ReactType(iReac)))
      CASE('R')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                     * GEO%Volume(1)**2 / (dt &
                     * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                     * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,2)) &
                     * Species(ChemReac%DefinedReact(iReac,1,3))%MacroParticleFactor * NumSpec(nSpecies+1))
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) * GEO%Volume(1)**2 &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor / (dt * ChemReac%ReacCount(iReac)             &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))     &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2))    &
               * Species(ChemReac%DefinedReact(iReac,1,3))%MacroParticleFactor*NumSpec(nSpecies+1))
        END IF
      CASE('D')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                       * GEO%Volume(1) / (dt &
                       * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                       * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor* GEO%Volume(1) / (dt * ChemReac%ReacCount(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))         &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        END IF
      CASE('E')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                       * GEO%Volume(1) / (dt &
                       * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                       * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN 
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * GEO%Volume(1) / (dt * ChemReac%ReacCount(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))         &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        END IF
      CASE('i')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                       * GEO%Volume(1) / (dt &
                       * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                       * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * GEO%Volume(1) / (dt * ChemReac%ReacCount(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))         &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        END IF
      CASE('r')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                     * GEO%Volume(1)**2 / (dt &
                     * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                     * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,2)) &
                     * Species(ChemReac%DefinedReact(iReac,1,3))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,3)) )
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) * GEO%Volume(1)**2 &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor / (dt * ChemReac%ReacCount(iReac)             &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))     &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2))    &
               * Species(ChemReac%DefinedReact(iReac,1,3))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,3)) )
        END IF
      CASE('x')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                       * GEO%Volume(1) / (dt &
                       * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                       * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * GEO%Volume(1) / (dt * ChemReac%ReacCount(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))         &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        END IF
      CASE('iQK')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                       * GEO%Volume(1) / (dt &
                       * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                       * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * GEO%Volume(1) / (dt * ChemReac%ReacCount(iReac) &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))         &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2)))
        END IF
      CASE('rQK')
        IF (DSMC%ReservoirRateStatistic) THEN ! Calculation of rate constant through actual number of allowed reactions
          RRate(iReac) = ChemReac%NumReac(iReac) * Species(ChemReac%DefinedReact(iReac,2,1))%MacroParticleFactor &
                     * GEO%Volume(1)**2 / (dt &
                     * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,1)) &
                     * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,2)) &
                     * Species(ChemReac%DefinedReact(iReac,1,3))%MacroParticleFactor * NumSpec(ChemReac%DefinedReact(iReac,1,3)) )
        ! Calculation of rate constant through mean reaction probability (using mean reaction prob and sum of coll prob)
        ELSEIF(ChemReac%ReacCount(iReac).GT.0) THEN
          RRate(iReac) = ChemReac%NumReac(iReac) * ChemReac%ReacCollMean(iReac) * GEO%Volume(1)**2 &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor / (dt * ChemReac%ReacCount(iReac)             &
               * Species(ChemReac%DefinedReact(iReac,1,1))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,1))     &
               * Species(ChemReac%DefinedReact(iReac,1,2))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,2))    &
               * Species(ChemReac%DefinedReact(iReac,1,3))%MacroParticleFactor*NumSpec(ChemReac%DefinedReact(iReac,1,3)) )
        END IF
      END SELECT
    END IF
  END DO
  ChemReac%NumReac = 0
END SUBROUTINE ReacRates
#endif 

#if ( PP_TimeDiscMethod == 42)
SUBROUTINE ElectronicTransition (  Time, NumSpec )
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
  USE MOD_DSMC_Vars,          ONLY: DSMC, SpecDSMC
  USE MOD_TimeDisc_Vars,      ONLY: dt
  USE MOD_Particle_Vars,      ONLY: nSpecies, Species
  USE MOD_Particle_Mesh_Vars, ONLY: GEO
  ! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
  ! OUTPUT VARIABLES
  REAL,INTENT(IN)                :: Time
  REAL,INTENT(IN)               :: NumSpec(:)
  INTEGER                        :: iSpec, iSpec2, iQua1, iQua2, MaxElecQua
! accary of kf
!===================================================================================================================================

  IF ( DSMC%ElectronicModel ) THEN
  ! kf = d n_of_N^i / dt / ( n_of_N^i n_of_M) )
    DO iSpec = 1, nSpecies
      IF ( SpecDSMC(iSpec)%InterID .ne. 4 ) THEN
        DO iSpec2 = 1, nSpecies
     ! calculaction of kf for each reaction
!       MaxElecQua = SpecDSMC(iSpec)%MaxElecQuant
          MaxElecQua = 2
        ! for first tests only consider the first 10 transition levels
          DO iQua1 = 0, MaxElecQua
            DO iQua2 = 0, MaxElecQua
          ! calculate kf
          ! kf = ( d n_of_N^i / d t )  / ( n_of_N^i n_of_M )
              IF ( (NumSpec(iSpec2) .ne. 0) .and. (SpecDSMC(iSpec)%levelcounter(iQua1) .ne. 0 ) ) THEN
                SpecDSMC(iSpec)%ElectronicTransition(iSpec2,iQua1,iQua2) = &
                                      SpecDSMC(iSpec)%ElectronicTransition(iSpec2,iQua1,iQua2) * GEO%Volume(1) &
                                    / ( dt * SpecDSMC(iSpec)%levelcounter(iQua1) * NumSpec(iSpec2) *           &
                                        Species(iSpec2)%MacroParticleFactor )
              END IF
!             print*,SpecDSMC(iSpec)%ElectronicTransition(iSpec2,iQua1,iQua2)
            END DO
          END DO
        END DO
      END IF
    END DO
    CALL WriteEletronicTransition( Time )
    ! nullyfy
    DO iSpec = 1, nSpecies
      IF(SpecDSMC(iSpec)%InterID.ne.4)THEN
        SpecDSMC(iSpec)%ElectronicTransition = 0
      END IF
    END DO
  END IF
!-----------------------------------------------------------------------------------------------------------------------------------
END SUBROUTINE
#endif

#if ( PP_TimeDiscMethod == 42)
SUBROUTINE WriteEletronicTransition ( Time )
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
  USE MOD_Globals,            ONLY: Getfreeunit
  USE MOD_DSMC_Vars,          ONLY: DSMC, SpecDSMC
  USE MOD_Particle_Vars,      ONLY: nSpecies
!   ! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
  ! OUTPUT VARIABLES
  REAL,INTENT(IN)                :: Time
  INTEGER                        :: iSpec, iSpec2, iunit, iQua1, iQua2, MaxElecQua, ii
  CHARACTER(LEN=128)             :: FileNameTransition
  LOGICAL                        :: bExist
! accary of kf
!-----------------------------------------------------------------------------------------------------------------------------------
  bExist = .false.
  IF ( DSMC%ElectronicModel ) THEN
  ! kf = d n_of_N^i / dt / ( n_of_N^i n_of_M) )
    DO iSpec = 1, nSpecies
      IF (SpecDSMC(iSpec)%InterID .ne. 4 ) THEN
!        MaxElecQua = SpecDSMC(iSpec)%MaxElecQuant
        MaxElecQua = 2
        ! output to transition file
        FileNameTransition = trim(SpecDSMC(iSpec)%Name)//'_Transition.csv'
        INQUIRE( FILE = FileNameTransition, EXIST=bExist)
!-----------------------------------------------------------------------------------------------------------------------------------
        IF ( bExist .EQV. .false. ) THEN 
          iunit=GETFREEUNIT()
          OPEN(UNIT=iunit,FILE=FileNameTransition,FORM='FORMATTED',STATUS='UNKNOWN')
!         ! writing header
          WRITE(iunit,'(A6,A5)',ADVANCE='NO') 'TIME', ' '
          ii = 2
          DO iSpec2 = 1, nSpecies
            DO iQua1 = 0, MaxElecQua
              DO iQua2 = 0, MaxElecQua
                WRITE(iunit,'(I3.3,A,I2.2,A,I2.2,A,I2.2,A)', ADVANCE='NO') ii,'_Species',iSpec2,'_',iQua1,'_to_',iQua2,'  '
                WRITE(iunit,'(A1)',ADVANCE='NO') ','
                ii = ii + 1
              END DO
            END DO
          END DO
        ELSE
!-----------------------------------------------------------------------------------------------------------------------------------
!         ! writing header
          iunit=GETFREEUNIT()
          OPEN(unit=iunit,FILE=FileNameTransition,FORM='Formatted',POSITION='APPEND',STATUS='old')
          WRITE(iunit,104,ADVANCE='NO') TIME
          DO iSpec2 = 1, nSpecies
!       ! calculaction of kf for each reaction
            DO iQua1 = 0, MaxElecQua
              DO iQua2 = 0, MaxElecQua
              ! write values to file
                WRITE(iunit,'(A1)',ADVANCE='NO') ','
                WRITE(iunit,104,ADVANCE='NO') SpecDSMC(iSpec)%ElectronicTransition(iSpec2,iQua1,iQua2)
              END DO
            END DO
          END DO
          WRITE(iunit,'(A)') ' '
        END IF
        CLOSE(unit = iunit)
      END IF
    END DO
!-----------------------------------------------------------------------------------------------------------------------------------
  END IF
!-----------------------------------------------------------------------------------------------------------------------------------
104    FORMAT (e25.14)
!-----------------------------------------------------------------------------------------------------------------------------------
END SUBROUTINE WriteEletronicTransition
#endif

SUBROUTINE TrackingParticlePosition(time) 
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_Vars,          ONLY:PartState, PDM, PEM
USE MOD_Particle_MPI_Vars,      ONLY:PartMPI
USE MOD_Particle_Analyze_Vars,  ONLY:printDiff,printDiffVec,printDiffTime
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)                :: time
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: i,iunit,iPartState
CHARACTER(LEN=60) :: TrackingFilename!,hilf
LOGICAL            :: fexist
REAL               :: diffPos,diffVelo
!===================================================================================================================================

iunit=GETFREEUNIT()
!WRITE(UNIT=hilf,FMT='(I6.6)') MyRank
!TrackingFilename = ('MyRank'//TRIM(hilf)//'_ParticlePosition.csv')
TrackingFilename = ('ParticlePosition.csv')

INQUIRE(FILE = TrackingFilename, EXIST=fexist)
IF(.NOT.fexist) THEN 
 IF(PartMPI%MPIRoot)THEN
   iunit=GETFREEUNIT()
   OPEN(UNIT=iunit,FILE=TrackingFilename,FORM='FORMATTED',STATUS='UNKNOWN')
   !CALL FLUSH (iunit)
    ! writing header
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'TIME', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartNum', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartPosX', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartPosY', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartPosZ', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartVelX', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartVelY', ' '
    WRITE(iunit,'(A1)',ADVANCE='NO') ','
    WRITE(iunit,'(A8,A5)',ADVANCE='NO') 'PartVelZ', ' '
    CLOSE(iunit)
  END IF
ELSE
  iunit=GETFREEUNIT()
  OPEN(unit=iunit,FILE=TrackingFileName,FORM='Formatted',POSITION='APPEND',STATUS='old')
  !CALL FLUSH (iunit)
  DO i=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(i)) THEN
      WRITE(iunit,104,ADVANCE='NO') TIME
      WRITE(iunit,'(A1)',ADVANCE='NO') ','
      WRITE(iunit,'(I12)',ADVANCE='NO') i
      DO iPartState=1,6
        WRITE(iunit,'(A1)',ADVANCE='NO') ','
        WRITE(iunit,104,ADVANCE='NO') PartState(i,iPartState)
      END DO
      WRITE(iunit,'(A1)',ADVANCE='NO') ','
      WRITE(iunit,'(I12)',ADVANCE='NO') PEM%Element(i)
      WRITE(iunit,'(A)') ' '
     END IF
  END DO
  CLOSE(iunit)
END IF
IF (printDiff) THEN
  diffPos=0.
  diffVelo=0.
  IF (time.GE.printDiffTime) THEN
    printDiff=.FALSE.
    DO iPartState=1,3
      diffPos=diffPos+(printDiffVec(iPartState)-PartState(1,iPartState))**2
      diffVelo=diffVelo+(printDiffVec(iPartState+3)-PartState(1,iPartState+3))**2
    END DO
    WRITE(*,'(A,e24.14,x,e24.14)') 'L2-norm from printDiffVec: ',SQRT(diffPos),SQRT(diffVelo)
  END IF
END IF
104    FORMAT (e25.14)

END SUBROUTINE TrackingParticlePosition

Function CalcEkinPart(iPart) 
!===================================================================================================================================
! computes the kinetic energy of one particle
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Equation_Vars,          ONLY : c2, c2_inv
USE MOD_Particle_Vars,          ONLY : PartState, PartSpecies, Species
USE MOD_PARTICLE_Vars,          ONLY : PartMPF, usevMPF
USE MOD_Particle_Vars,          ONLY : PartLorentzType 
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER,INTENT(IN)                 :: iPart
REAL                               :: CalcEkinPart
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                               :: partV2, gamma1, Ekin
!===================================================================================================================================

IF (PartLorentzType.EQ.5)THEN
  ! gamma v is pushed instead of gamma, therefore, only the relativistic kinetic energy is computed
  ! compute gamma
  gamma1=SQRT(1.0+DOT_PRODUCT(PartState(iPart,4:6),PartState(iPart,4:6))*c2_inv)
  IF(usevMPF)THEN
    Ekin=PartMPF(iPart)*(gamma1-1.0)*Species(PartSpecies(iPart))%MassIC*c2
  ELSE
    Ekin= (gamma1-1.0)* Species(PartSpecies(iPart))%MassIC*Species(PartSpecies(iPart))%MacroParticleFactor*c2
  END IF
ELSE
  partV2 = PartState(iPart,4) * PartState(iPart,4) &
         + PartState(iPart,5) * PartState(iPart,5) &
         + PartState(iPart,6) * PartState(iPart,6)
  
  IF(usevMPF)THEN
    IF (partV2.LT.1e6)THEN
      Ekin= 0.5 * Species(PartSpecies(iPart))%MassIC * partV2 * PartMPF(iPart)            
    ELSE
      gamma1=partV2*c2_inv
      gamma1=1.0/SQRT(1.-gamma1)
      Ekin=PartMPF(iPart)*(gamma1-1.0)*Species(PartSpecies(iPart))%MassIC*c2
    END IF ! ipartV2
  ELSE ! novMPF
    IF (partV2.LT.1e6)THEN
      Ekin= 0.5*Species(PartSpecies(iPart))%MassIC*partV2* Species(PartSpecies(iPart))%MacroParticleFactor
    ELSE
      gamma1=partV2*c2_inv
      gamma1=1.0/SQRT(1.-gamma1)
      Ekin= (gamma1-1.0)* Species(PartSpecies(iPart))%MassIC*Species(PartSpecies(iPart))%MacroParticleFactor*c2
    END IF ! ipartV2
  END IF ! usevMPF
END IF
CalcEkinPart=Ekin
END FUNCTION CalcEkinPart
 
SUBROUTINE FinalizeParticleAnalyze()
!===================================================================================================================================
! Finalizes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Particle_Analyze_Vars,ONLY:ParticleAnalyzeInitIsDone
! IMPLICIT VARIABLE HANDLINGDGInitIsDone
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
ParticleAnalyzeInitIsDone = .FALSE.
END SUBROUTINE FinalizeParticleAnalyze
#endif /*PARTICLES*/


END MODULE MOD_Particle_Analyze

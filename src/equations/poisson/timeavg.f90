#include "boltzplatz.h"

!==================================================================================================================================
!> Routine performing time averaging of variables and the preparation to computing fluctuations
!> The terms computed in this routine are therefore the TimeAvg: \f$ \overline{U} \f$ and 
!> the squared solution denoted by Fluc: \f$ \overline{U^2} \f$ 
!> the fluctuations are the RMS values
!> list structure: 1:PP_nVar - Varnames of equationsystem
!>                 PP_nVar+  - additional variables
!==================================================================================================================================
MODULE MOD_TimeAverage
! MODULES
IMPLICIT NONE
PRIVATE

!----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE InitTimeAverage
  MODULE PROCEDURE InitTimeAverage
END INTERFACE

INTERFACE FinalizeTimeAverage
  MODULE PROCEDURE FinalizeTimeAverage
END INTERFACE

INTERFACE CalcTimeAverage
  MODULE PROCEDURE CalcTimeAverage
END INTERFACE

PUBLIC::InitTimeAverage, FinalizeTimeAverage, CalcTimeAverage
!==================================================================================================================================
CONTAINS

SUBROUTINE InitTimeAverage()
!==================================================================================================================================
!> Initializes the time averaging variables and fluctuation/ RMS fluctuation quantities to required time averaged variables
!> (e.g. if Ex fluctuations are to be computed, the time averages of the Ex are computed, too
!> - only variables in the equation system can be averaged
!==================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_ReadInTools,    ONLY: CNTSTR,GETSTR,GETLOGICAL,GETINT
USE MOD_Mesh_Vars,      ONLY: nElems
USE MOD_Timeaverage_Vars 
USE MOD_Equation_Vars,  ONLY: StrVarNames
#ifdef PARTICLES
USE MOD_Particle_Vars,  ONLY: nSpecies
USE MOD_PICDepo_Vars,   ONLY: DoDeposition
#endif /*PARTICLES*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iVar,iVar2
CHARACTER(LEN=255),ALLOCATABLE :: VarNamesAvgIni(:), VarNamesAvgList(:), VarNamesFlucList(:)
CHARACTER(LEN=255),ALLOCATABLE :: VarNamesFlucIni(:)
LOGICAL,ALLOCATABLE            :: hasAvgVars(:)
#ifdef PARTICLES
INTEGER                        :: iSpec,iCounter
CHARACTER(LEN=2)               :: strhelp
#endif /*PARTICLES*/
!==================================================================================================================================

nVarAvg  = CNTSTR('VarNameAvg')
nVarFluc = CNTSTR('VarNameFluc')
IF((nVarAvg.EQ.0).AND.(nVarFluc.EQ.0))THEN
  CALL CollectiveStop(__STAMP__, &
    'No quantities for time averaging have been specified. Please specify quantities or disable time averaging!')
#if FV_ENABLED
ELSE
  CALL CollectiveStop(__STAMP__, &
    'Timeaveraging has not been implemented for FV yet!')
#endif
END IF

! Define variables to be averaged
nMaxVarAvg=5
#ifdef PARTICLES
nMaxVarAvg=nMaxVarAvg+9*nSpecies
#endif /*PARTICLES*/
ALLOCATE(VarNamesAvgList(nMaxVarAvg))

DO iVar=1,4
  VarNamesAvgList(iVar)=StrVarNames(iVar)
END DO ! iVar=1,PP_nVar
VarNamesAvgList(5)='ElectricFieldMagnitude'

#ifdef PARTICLES
iCounter=5
DO iSpec=1,nSpecies
  WRITE(strhelp,'(I2.2)') iSpec
  VarnamesAvgList(iCounter+1)=TRIM('PowerDensityX-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+2)=TRIM('PowerDensityY-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+3)=TRIM('PowerDensityZ-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+4)=TRIM('PowerDensity-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+5)=TRIM('ChargeDensity-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+6)=TRIM('CurrentDensityX-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+7)=TRIM('CurrentDensityY-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+8)=TRIM('CurrentDensityZ-Spec')//TRIM(strhelp)
  VarnamesAvgList(iCounter+9)=TRIM('CurrentDensity-Spec')//TRIM(strhelp)
  iCounter=iCounter+9
END DO
#endif /*PARTICLES*/

nMaxVarFluc=5
#ifdef PARTICLES
nMaxVarFluc=nMaxVarFluc+9*nSpecies
#endif /*PARTICLES*/
ALLOCATE(VarNamesFlucList(nMaxVarFluc),hasAvgVars(nMaxVarFluc))
hasAvgVars=.TRUE.
!define fluctuation variables
DO iVar=1,4
  VarNamesFlucList(iVar)=StrVarNames(iVar)
END DO ! iVar=1,PP_nVar
VarNamesFlucList(5)='ElectricFieldMagnitude'

#ifdef PARTICLES
iCounter=5
DO iSpec=1,nSpecies
  WRITE(strhelp,'(I2.2)') iSpec
  VarnamesFlucList(iCounter+1)=TRIM('PowerDensityX-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+2)=TRIM('PowerDensityY-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+3)=TRIM('PowerDensityZ-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+4)=TRIM('PowerDensity-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+5)=TRIM('ChargeDensity-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+6)=TRIM('CurrentDensityX-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+7)=TRIM('CurrentDensityY-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+8)=TRIM('CurrentDensityZ-Spec')//TRIM(strhelp)
  VarnamesFlucList(iCounter+9)=TRIM('CurrentDensity-Spec')//TRIM(strhelp)
  iCounter=iCounter+9
END DO
#endif /*PARTICLES*/

! Read VarNames from ini file
ALLOCATE(VarNamesAvgIni(nVarAvg),VarNamesFlucIni(nVarFluc))
DO iVar=1,nVarAvg
  VarNamesAvgIni(iVar)=GETSTR('VarNameAvg')
END DO
DO iVar=1,nVarFluc
  VarNamesFlucIni(iVar)=GETSTR('VarNameFluc')
END DO

! Check which variables have to be calculated and create mappings to global variable index (1:nVarout)
! CalcAvgTmp(1,:) for normal variables, CalcAvgTmp(2,:) for fluctuations
ALLOCATE(CalcAvg(nMaxVarAvg),CalcFluc(nMaxVarFluc))
CalcAvg=.FALSE.
CalcFluc=.FALSE.

! check each average from ini file
DO iVar=1,nVarAvg
  ! check if avg from ini file is in avg list
  iVar2 = GETMAPBYNAME(VarNamesAvgIni(iVar),VarNamesAvgList,nMaxVarAvg)
  IF(iVar2.NE.-1)THEN
    CalcAvg(iVar2) = .TRUE.
  ELSE
    CALL CollectiveStop(__STAMP__, &
    'Specified varname does not exist: ' // VarNamesAvgIni(iVar))
  END IF
END DO

! check each fluctuation from ini file
DO iVar=1,nVarFluc
  ! check if fluc from ini file is in fluc list
  iVar2 = GETMAPBYNAME(VarNamesFlucIni(iVar),VarNamesFlucList,nMaxVarFluc)
  IF(iVar2.NE.-1)THEN
    CalcFluc(iVar2) = .TRUE.
  ELSE
    CALL CollectiveStop(__STAMP__, &
    'Specified varname does not exist: ' // VarNamesFlucIni(iVar))
  END IF

  ! if fluctuation is set also compute base variable
  iVar2 = GETMAPBYNAME(VarNamesFlucIni(iVar),VarNamesAvgList,nMaxVarAvg)
  IF(iVar2.NE.-1) CalcAvg(iVar2) = .TRUE.
END DO

! particles, additional marking for samling
#ifdef PARTICLES
iCounter=5
ALLOCATE(DoPowerDensity(1:nSpecies))
DoPowerDensity=.FALSE.
nSpecPowerDensity=0
IF(DoDeposition)THEN ! compute powerdensity only if particles are deposited
  DO iSpec=1,nSpecies
    IF(ANY(CalcAvg(iCounter+1:iCounter+5))) THEN
      DoPowerDensity(iSpec)=.TRUE.
      nSpecPowerDensity=nSpecPowerDensity+1
    END IF
    iCounter=iCounter+9
  END DO
  IF(nSpecPowerDensity.GT.0) ALLOCATE(PowerDensity(1:7,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems,1:nSpecPowerDensity))
END IF
#endif /*PARTICELS*/


! For fluctuations with mixed base vars
! nothing to do

! recount nVarAvg
nVarAvg=0 ! recount nVarAvg
DO iVar=1,nMaxVarAvg
  IF(CalcAvg(iVar)) nVarAvg=nVarAvg+1
END DO

! Set indices (iAvg,iFluc) and Varnames
ALLOCATE(VarNamesFlucOut(nVarFluc),VarNamesAvgOut(nVarAvg))
ALLOCATE(iAvg(nMaxVarAvg),iFluc(nMaxVarFluc))
! iAvg     -> Mapping from VariableList to index in UAvg array
! iFluc    -> Mapping from index in UFluc array to index in UAvg array
!             (e.g. for mixed term uv: iFluc(1,1) -> u iFluc(2,1) -> v)

VarNamesFlucOut(:)=''
VarNamesAvgOut(:)=''
nVarAvg=0
nVarFluc=0
iAvg=0
iFluc=0
! Build map for avg
DO iVar=1,nMaxVarAvg
  IF(CalcAvg(iVar))THEN
    nVarAvg=nVarAvg+1
    iAvg(iVar)=nVarAvg
    VarNamesAvgOut(nVarAvg) = TRIM(VarNamesAvgList(iVar))
  END IF
END DO
! Build map from fluclist to calcfluc
DO iVar=1,nMaxVarFluc
  IF(CalcFluc(iVar).AND.hasAvgVars(iVar))THEN
    nVarFluc=nVarFluc+1
    iFluc(iVar)=nVarFluc
    VarNamesFlucOut(nVarFluc) = TRIM(VarNamesFlucList(iVar))
  END IF
END DO
nVarFlucHasAvg=nVarFluc
ALLOCATE(FlucAvgMap(2,nVarFlucHasAvg))
FlucAvgMap=0
DO iVar=1,nMaxVarFluc
  IF(CalcFluc(iVar).AND.(.NOT.hasAvgVars(iVar)))THEN
    nVarFluc=nVarFluc+1
    iFluc(iVar)=nVarFluc
    VarNamesFlucOut(nVarFluc) = TRIM(VarNamesFlucList(iVar))
  END IF
END DO

! set map from fluc array to avg array needed to compute fluc
DO iVar=1,nMaxVarFluc
  IF((iFluc(iVar).NE.0).AND.hasAvgVars(iVar))THEN
    iVar2 = GETMAPBYNAME(VarNamesFlucList(iVar),VarNamesAvgList,nMaxVarAvg)
    IF(iVar2.GT.0) FlucAvgMap(:,iFluc(iVar))=iAvg(iVar2)
  END IF
END DO

! Allocate arrays
ALLOCATE(UAvg(nVarAvg,0:PP_N,0:PP_N,0:PP_N,nElems),UFluc(nVarFluc,0:PP_N,0:PP_N,0:PP_N,nElems))
UAvg = 0.
UFluc = 0.
dtOld=0.
dtAvg=0.

DEALLOCATE(VarNamesAvgList,VarNamesAvgIni,VarNamesFlucIni,VarNamesFlucList)
END SUBROUTINE InitTimeAverage


FUNCTION GETMAPBYNAME(VarName,VarNameList,nVarList)
!==================================================================================================================================
!> Return index of string VarName in array VarNameList
!==================================================================================================================================
! MODULES
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)    :: VarName                 !< string to be compared
CHARACTER(LEN=*),INTENT(IN)    :: VarNameList(nVarList)   !< list of strings to be searched
INTEGER,INTENT(IN)             :: nVarList                !< length of list
INTEGER                        :: GETMAPBYNAME            !< index of VarName in VarNameList
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: i
!==================================================================================================================================
GETMAPBYNAME=-1
DO i=1,nVarList
  IF(TRIM(VarName).EQ.TRIM(VarNameList(i)))THEN
    GETMAPBYNAME=i
    RETURN
  END IF
END DO
END FUNCTION


SUBROUTINE CalcTimeAverage(Finalize,dt,t,tFuture)
!==================================================================================================================================
!> Compute time averages by trapezoidal rule
!==================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_DG_Vars          ,ONLY: U
USE MOD_Mesh_Vars        ,ONLY: MeshFile,nElems
USE MOD_HDF5_Output      ,ONLY: WriteTimeAverage
USE MOD_Equation_Vars    ,ONLY: E
USE MOD_Timeaverage_Vars ,ONLY: UAvg,UFluc,CalcAvg,iAvg,FlucAvgMap,dtAvg,dtold,nVarAvg,nVarFluc,nVarFlucHasAvg &
                               ,VarnamesAvgOut,VarNamesFlucOut
#ifdef PARTICLES
USE MOD_Timeaverage_Vars ,ONLY: PowerDensity,DoPowerDensity
USE MOD_Particle_Vars,    ONLY: nSpecies
USE MOD_Particle_Analyze, ONLY: CalcPowerDensity
#endif /*Particles*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
LOGICAL,INTENT(IN)              :: Finalize               !< finalized trapezoidal rule and output file
REAL,INTENT(IN)                 :: dt                     !< current timestep for averaging
REAL,INTENT(IN)                 :: t                      !< current simulation time
REAL,INTENT(IN)                 :: tFuture                !< future simulation time
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: i,j,k,iElem,iVar
REAL                            :: dtStep
REAL                            :: tmpVars(nVarAvg,0:PP_N,0:PP_N,0:PP_N)
#ifdef PARTICLES
INTEGER                         :: iSpec,iSpec2,iCounter
#endif /*Particles*/
!----------------------------------------------------------------------------------------------------------------------------------
dtStep = (dtOld+dt)*0.5
IF(Finalize) dtStep = dt*0.5
dtAvg  = dtAvg+dtStep
dtOld  = dt

#ifdef PARTICLES
IF(ANY(DoPowerDensity))THEN
  CALL CalcPowerDensity()
END IF
#endif /*Particles*/

DO iElem=1,nElems

  ! Compute time averaged variables and fluctuations of these variables
  ! loop over all variables
  DO iVar=1,1
    IF(CalcAvg(1)) tmpVars(iAvg(1),:,:,:) = U(1,:,:,:,iElem)
  END DO ! iVar=1,PP_nVar
  IF(CalcAvg(2)) tmpVars(iAvg(2),:,:,:) = E(1,:,:,:,iElem)
  IF(CalcAvg(3)) tmpVars(iAvg(3),:,:,:) = E(2,:,:,:,iElem)
  IF(CalcAvg(4)) tmpVars(iAvg(4),:,:,:) = E(3,:,:,:,iElem)

  ! ElectricFieldMagnitude
  IF(CalcAvg(5))THEN  
    DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
      tmpVars(iAvg(5),i,j,k)=SQRT(SUM(E(1:3,i,j,k,iElem)**2))
    END DO; END DO; END DO
  END IF

#ifdef PARTICLES
  iCounter=5
  iSpec2=0
  DO iSpec=1,nSpecies
    iVar=iCounter
    IF(DoPowerDensity(iSpec))THEN
      iSpec2=iSpec2+1
      ! PowerDensity 1:3
      IF(CalcAvg(iCounter+1)) tmpVars(iAvg(iVar+1),:,:,:) = PowerDensity(1,:,:,:,iElem,iSpec2)
      IF(CalcAvg(iCounter+2)) tmpVars(iAvg(iVar+2),:,:,:) = PowerDensity(2,:,:,:,iElem,iSpec2)
      IF(CalcAvg(iCounter+3)) tmpVars(iAvg(iVar+3),:,:,:) = PowerDensity(3,:,:,:,iElem,iSpec2)
      ! Mag(PowerDensity)
      IF(CalcAvg(iCounter+4))THEN
        DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
          tmpVars(iAvg(iVar+4),i,j,k) = SQRT(DOT_PRODUCT(PowerDensity(1:3,i,j,k,iElem,iSpec2),PowerDensity(1:3,i,j,k,iElem,iSpec2)))
        END DO; END DO; END DO
      END IF
      IF(CalcAvg(iCounter+5)) tmpVars(iAvg(iVar+5),:,:,:) = PowerDensity(4,:,:,:,iElem,iSpec2)
      ! CurrentDensity 1:3
      IF(CalcAvg(iCounter+6)) tmpVars(iAvg(iVar+6),:,:,:) = PowerDensity(5,:,:,:,iElem,iSpec2)
      IF(CalcAvg(iCounter+7)) tmpVars(iAvg(iVar+7),:,:,:) = PowerDensity(6,:,:,:,iElem,iSpec2)
      IF(CalcAvg(iCounter+8)) tmpVars(iAvg(iVar+8),:,:,:) = PowerDensity(7,:,:,:,iElem,iSpec2)
      ! Mag(CurrentDensity)
      IF(CalcAvg(iCounter+9))THEN
        DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
          tmpVars(iAvg(iVar+9),i,j,k) = SQRT(DOT_PRODUCT(PowerDensity(5:7,i,j,k,iElem,iSpec2),PowerDensity(5:7,i,j,k,iElem,iSpec2)))
        END DO; END DO; END DO
      END IF
    END IF
    iCounter=iCounter+9
  END DO ! iSpec=1,nSpecies
#endif /*Particles*/

  ! compute average
  UAvg(:,:,:,:,iElem)= UAvg (:,:,:,:,iElem) + tmpVars(1:nVarAvg,:,:,:)*dtStep
  IF(nVarFluc.GT.0)&
    UFluc(1:nVarFlucHasAvg,:,:,:,iElem) = UFluc(1:nVarFlucHasAvg,:,:,:,iElem) + &
                                 tmpVars(FlucAvgMap(1,1:nVarFlucHasAvg),:,:,:)*tmpVars(FlucAvgMap(2,1:nVarFlucHasAvg),:,:,:)*dtStep

END DO ! iElem

! Calc time average and write solution to file
IF(Finalize)THEN
  UAvg =UAvg /dtAvg
  UFluc=UFluc/dtAvg
  CALL WriteTimeAverage(TRIM(MeshFile),t,tFuture,VarNamesAvgOut,VarNamesFlucOut,UAvg,UFluc,dtAvg,nVarAvg,nVarFluc)
  UAvg=0.
  UFluc=0.
  dtAvg=0.
  dtOld=0.
END IF

END SUBROUTINE CalcTimeAverage


SUBROUTINE FinalizeTimeAverage()
!==================================================================================================================================
!> Finalizes the time averaging routines
!==================================================================================================================================
! MODULES
USE MOD_Timeaverage_Vars
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!==================================================================================================================================
SDEALLOCATE(CalcAvg)
SDEALLOCATE(iAvg)
SDEALLOCATE(iFluc)
SDEALLOCATE(UAvg)
SDEALLOCATE(UFluc)
SDEALLOCATE(VarNamesAvgOut)
SDEALLOCATE(VarNamesFlucOut)
#ifdef PARTICLES
SDEALLOCATE(DoPowerDensity)
SDEALLOCATE(PowerDensity)
#endif /*PARTICLES*/
END SUBROUTINE FinalizeTimeAverage

END MODULE MOD_TimeAverage

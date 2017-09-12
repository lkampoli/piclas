#include "boltzplatz.h"


MODULE MOD_PML
!===================================================================================================================================
!  
!===================================================================================================================================
! MODULES
USE MOD_io_HDF5
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE InitPML
  MODULE PROCEDURE InitPML
END INTERFACE
INTERFACE FinalizePML
  MODULE PROCEDURE FinalizePML
END INTERFACE
INTERFACE PMLTimeRamping
  MODULE PROCEDURE PMLTimeRamping
END INTERFACE
INTERFACE CalcPMLSource
  MODULE PROCEDURE CalcPMLSource
END INTERFACE
INTERFACE PMLTimeDerivative
  MODULE PROCEDURE PMLTimeDerivative
END INTERFACE

PUBLIC::InitPML,FinalizePML,PMLTimeRamping,CalcPMLSource,PMLTimeDerivative
!===================================================================================================================================
CONTAINS

SUBROUTINE InitPML()
!===================================================================================================================================
!  Initialize perfectly matched layer
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_ReadInTools
USE MOD_PML_Vars
USE MOD_HDF5_output,     ONLY: GatheredWriteArray,GenerateFileSkeleton,WriteAttributeToHDF5,WriteHDF5Header
USE MOD_HDF5_output,     ONLY: WritePMLzetaGlobalToHDF5
USE MOD_Interfaces,      ONLY: FindInterfacesInRegion,FindElementInRegion,CountAndCreateMappings
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER              :: I
!===================================================================================================================================
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT PML...'
!===================================================================================================================================
! Readin
!===================================================================================================================================
DoPML                      = GETLOGICAL('DoPML','.FALSE.')
PMLzeta0                   = GETREAL('PMLzeta0','0.')
PMLalpha0                  = GETREAL('PMLalpha0','0.')
xyzPhysicalMinMax(1:6)     = GETREALARRAY('xyzPhysicalMinMax',6,'0.0,0.0,0.0,0.0,0.0,0.0')
xyzPMLzetaShapeOrigin(1:3) = GETREALARRAY('xyzPMLzetaShapeOrigin',3,'0.0,0.0,0.0')
xyzPMLMinMax(1:6)          = GETREALARRAY('xyzPMLMinMax',6,'0.0,0.0,0.0,0.0,0.0,0.0')
! use xyzPhysicalMinMax before xyzPMLMinMax: 1.) check for xyzPhysicalMinMax 2.) check for xyzPMLMinMax
IF(ALMOSTEQUAL(MAXVAL(xyzPhysicalMinMax),MINVAL(xyzPhysicalMinMax)))THEN ! if still the initialized values
  xyzPhysicalMinMax(1:6)=(/-HUGE(1.),HUGE(1.),-HUGE(1.),HUGE(1.),-HUGE(1.),HUGE(1.)/)
  IF(ALMOSTEQUAL(MAXVAL(xyzPMLMinMax),MINVAL(xyzPMLMinMax)))THEN ! if still the initialized values
    xyzPMLMinMax(1:4)=(/-HUGE(1.),HUGE(1.),-HUGE(1.),HUGE(1.)/)
    usePMLMinMax=.FALSE. ! ! xyzPhysicalMinMax and xyzPMLMinMax are undefined -> use HUGE for both
    SWRITE(UNIT_stdOut,'(A)')"no PML region supplied, setting xyzPhysicalMinMax(1:6): Setting [+-HUGE]"
    SWRITE(UNIT_stdOut,'(A)')"no PML region supplied, setting xyzPMLMinMax(1:6)     : Setting [+-HUGE]"
  ELSE
    SWRITE(UNIT_stdOut,'(A)')"PML region supplied via xyzPMLMinMax(1:6)"
    usePMLMinMax=.TRUE. ! xyzPhysicalMinMax is undefined but xyzPMLMinMax is not
  END IF
ELSE
  SWRITE(UNIT_stdOut,'(A)')"PML region supplied via xyzPhysicalMinMax(1:6)"
END IF
! display ranges of PML region depending on usePMLMinMax
SWRITE(UNIT_stdOut,'(A,L)') 'usePMLMinMax=',usePMLMinMax
IF(.NOT.usePMLMinMax)THEN
  SWRITE(UNIT_stdOut,'(A)') '  Ranges for xyzPhysicalMinMax(1:6) are'
  SWRITE(UNIT_stdOut,'(A)') '       [        x-dir         ] [        y-dir         ] [         z-dir        ]'
  SWRITE(UNIT_stdOut,'(A)',ADVANCE='NO') '  MIN'
  DO I=1,3
    SWRITE(UNIT_stdOut,OUTPUTFORMAT,ADVANCE='NO')  xyzPhysicalMinMax(2*I-1)
  END DO
  SWRITE(UNIT_stdOut,'(A)') ''
  SWRITE(UNIT_stdOut,'(A)',ADVANCE='NO') '  MAX'
  DO I=1,3
    SWRITE(UNIT_stdOut,OUTPUTFORMAT,ADVANCE='NO')  xyzPhysicalMinMax(2*I)
  END DO
  SWRITE(UNIT_stdOut,'(A)') ''
ELSE
  SWRITE(UNIT_stdOut,'(A)') 'Ranges for xyzPMLMinMax(1:6) are'
  SWRITE(UNIT_stdOut,'(A)') '       [        x-dir         ] [        y-dir         ] [         z-dir        ]'
  SWRITE(UNIT_stdOut,'(A)',ADVANCE='NO') '  MIN'
  DO I=1,3
    SWRITE(UNIT_stdOut,OUTPUTFORMAT,ADVANCE='NO')  xyzPMLMinMax(2*I-1)
  END DO
  SWRITE(UNIT_stdOut,'(A)') ''
  SWRITE(UNIT_stdOut,'(A)',ADVANCE='NO') '  MAX'
  DO I=1,3
    SWRITE(UNIT_stdOut,OUTPUTFORMAT,ADVANCE='NO')  xyzPMLMinMax(2*I)
  END DO
  SWRITE(UNIT_stdOut,'(A)') ''
END IF

PMLzetaShape           = GETINT('PMLzetaShape','0')
PMLRampLength          = GETREAL('PMLRampLength','1.')
PMLspread              = GETINT('PMLspread','0')
PMLwriteFields         = GETINT('PMLwriteFields','0')
PMLzetaNorm            = GETLOGICAL('PMLzetaNorm','.FALSE.')

PMLprintInfo           = GETINT('PMLprintInfo','0') ! 0=only root prints PML info, 1=all procs print PML info
IF(PMLprintInfo.EQ.0)THEN
  PMLprintInfoProcs=1 ! only root prints infos
ELSE
  PMLprintInfoProcs=nProcessors ! all procs print their infos
END IF
! caution, in current version read in in mesh
! only for Maxwell, PP_nVar=8

DoPMLTimeRamp          = GETLOGICAL('DoPMLTimeRamp','.FALSE.')
PMLTimeRamptStart      = GETREAL('PMLTimeRamptStart','-1.')
PMLTimeRamptEnd        = GETREAL('PMLTimeRamptEnd','-1.')
PMLsDeltaT             = 0.0 ! init
PMLTimeRampCoeff       = 0.0 ! init
IF(ANY((/PMLTimeRamptStart,PMLTimeRamptEnd/).LT.0.0))THEN
  PMLTimeRamptStart    = 0.0
  PMLTimeRamptEnd      = 0.0
  DoPMLTimeRamp        = .FALSE.
ELSE
  IF(ALMOSTEQUALRELATIVE(PMLTimeRamptStart,PMLTimeRamptEnd,1E-3))THEN
    SWRITE(UNIT_stdOut,'(A)') ' WARNING: PML time ramp uses the same times for tStart and tEnd. Relative difference is < 1E-3'
    PMLsDeltaT         = 1e12 ! set no a very high value
  ELSE  
    IF(PMLTimeRamptStart.GT.PMLTimeRamptEnd)THEN
      CALL abort(&
      __STAMP__,&
      ' PMLTimeRamptStart must be smaller than PMLTimeRamptEnd.')
    END IF
    PMLsDeltaT         = 1/(PMLTimeRamptEnd-PMLTimeRamptStart)
    PMLTimeRampCoeff   = -PMLTimeRamptStart * PMLsDeltaT
  END IF
END IF
PMLTimeRamp            = 1.0 ! init

IF(.NOT.DoPML) THEN
  SWRITE(UNIT_stdOut,'(A)') ' PML region deactivated. '
  PMLnVar=0
  nPMLElems=0
  RETURN
ELSE
#if PP_nVar == 1
  CALL abort(__STAMP__,&
      'Equation system does not support a PML!',999,999.)
#endif
#if PP_nVar == 4
  CALL abort(__STAMP__,&
      'Equation system does not support a PML!',999,999.)
#endif
  PMLnVar=24
END IF

! find all elements in the PML region. Here: find all elements located outside of 'xyzPhysicalMinMax' 
IF(usePMLMinMax)THEN
  CALL FindElementInRegion(isPMLElem,xyzPMLMinMax,ElementIsInside=.TRUE.,DisplayInfoProcs=PMLprintInfoProcs)
ELSE
  CALL FindElementInRegion(isPMLElem,xyzPhysicalMinMax,ElementIsInside=.FALSE.,DisplayInfoProcs=PMLprintInfoProcs)
END IF

! find all faces in the PML region
CALL FindInterfacesInRegion(isPMLFace,isPMLInterFace,isPMLElem,PMLprintInfoProcs)

! Get number of PML Elems, Faces and Interfaces. Create Mappngs PML <-> physical region
CALL CountAndCreateMappings('PML',&
                            isPMLElem,isPMLFace,isPMLInterFace,&
                            nPMLElems,nPMLFaces, nPMLInterFaces,&
                            ElemToPML,PMLToElem,&
                            FaceToPML,PMLToFace,&
                            FaceToPMLInter,PMLInterToFace)

! nPMLElems is determined, now allocate the PML field correnspondingly
ALLOCATE(U2       (1:PMLnVar,0:PP_N,0:PP_N,0:PP_N,1:nPMLElems))        
ALLOCATE(U2t      (1:PMLnVar,0:PP_N,0:PP_N,0:PP_N,1:nPMLElems))
U2=0.
U2t=0.

! Set the damping profile function zeta=f(x,y) in the PML region
CALL SetPMLdampingProfile()

! create a HDF5 file containing the PMLzetaGlobal field
CALL WritePMLzetaGlobalToHDF5()

PMLInitIsDone=.TRUE.
SWRITE(UNIT_stdOut,'(A)')' INIT PML DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitPML



PURE SUBROUTINE PMLTimeRamping(t,RampingFactor)
!===================================================================================================================================
! set the scaling factor which ramps the damping factor over time
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_PML_Vars,      ONLY: PMLTimeRamptStart,PMLTimeRamptEnd,PMLsDeltaT,PMLTimeRampCoeff
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)    :: t
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)   :: RampingFactor
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!INTEGER             :: i,j,k,iPMLElem,m
!===================================================================================================================================
IF(t.LT.PMLTimeRamptStart)THEN
  RampingFactor = 0.0                             ! set PMLTimeRamp to 0.0
ELSEIF(t.GT.PMLTimeRamptEnd)THEN
  RampingFactor = 1.0                             ! set PMLTimeRamp to 1.0
ELSE
  RampingFactor = PMLsDeltaT*t + PMLTimeRampCoeff ! set PMLTimeRamp to [0,1]
END IF
END SUBROUTINE PMLTimeRamping


SUBROUTINE CalcPMLSource()
!===================================================================================================================================
! 
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,       ONLY: Ut
USE MOD_PML_Vars,      ONLY: nPMLElems,PMLToElem
USE MOD_PML_Vars,      ONLY: PMLzeta,U2,PMLTimeRamp
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: i,j,k,iPMLElem,m
!===================================================================================================================================
! sources for the standard variables
DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
  DO m=1,8
    Ut(m,i,j,k,PMLToElem(iPMLElem)) = Ut(m,i,j,k,PMLToElem(iPMLElem))  &
                                     -PMLTimeRamp*(&
                                        PMLzeta(1,i,j,k,iPMLElem)*U2(m*3-2,i,j,k,iPMLElem) +&   ! = 1,4,7,10,13,16,19,22
                                        PMLzeta(2,i,j,k,iPMLElem)*U2(m*3-1,i,j,k,iPMLElem) +&   ! = 2,5,8,11,12,17,20,23
                                        PMLzeta(3,i,j,k,iPMLElem)*U2(m*3  ,i,j,k,iPMLElem) )    ! = 3,6,9,12,15,18,21,24
  END DO
END DO; END DO; END DO !nPMLElems,k,j,i
END DO
END SUBROUTINE CalcPMLSource


SUBROUTINE PMLTimeDerivative()
!===================================================================================================================================
! 
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_PML_Vars,      ONLY: U2,U2t
USE MOD_PML_Vars,      ONLY: nPMLElems,PMLToElem,PMLnVar
USE MOD_Mesh_Vars,     ONLY: sJ
USE MOD_PML_Vars,      ONLY: PMLzetaEff,PMLTimeRamp
USE MOD_Equation_Vars, ONLY: fDamping
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: i,j,k,iPMLElem,iPMLVar
!===================================================================================================================================
! We have to take the inverse of the Jacobians into account
! the '-' sign is due to the movement of the term to the right-hand-side of the equation
DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
  DO iPMLVar=1,PMLnVar
    U2t(iPMLVar,i,j,k,iPMLElem) = - U2t(iPMLVar,i,j,k,iPMLElem) * sJ(i,j,k,PMLToElem(iPMLElem))
  END DO
END DO; END DO; END DO; END DO !nPMLElems,k,j,i


! Add Source Terms
DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
  U2t(1 : 3,i,j,k,iPMLElem) = U2t(1 : 3,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(1 : 3,i,j,k,iPMLElem) * PMLTimeRamp 
  U2t(4 : 6,i,j,k,iPMLElem) = U2t(4 : 6,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(4 : 6,i,j,k,iPMLElem) * PMLTimeRamp
  U2t(7 : 9,i,j,k,iPMLElem) = U2t(7 : 9,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(7 : 9,i,j,k,iPMLElem) * PMLTimeRamp
  U2t(10:12,i,j,k,iPMLElem) = U2t(10:12,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(10:12,i,j,k,iPMLElem) * PMLTimeRamp
  U2t(13:15,i,j,k,iPMLElem) = U2t(13:15,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(13:15,i,j,k,iPMLElem) * PMLTimeRamp
  U2t(16:18,i,j,k,iPMLElem) = U2t(16:18,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(16:18,i,j,k,iPMLElem) * PMLTimeRamp
  U2t(19:21,i,j,k,iPMLElem) = U2t(19:21,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(19:21,i,j,k,iPMLElem) * PMLTimeRamp
  U2t(22:24,i,j,k,iPMLElem) = U2t(22:24,i,j,k,iPMLElem) - PMLzetaEff(1:3,i,j,k,iPMLElem) * U2(22:24,i,j,k,iPMLElem) * PMLTimeRamp
END DO; END DO; END DO; END DO !nPMLElems,k,j,i


! 1.) DEBUGPML: apply the damping factor also to PML source terms
! copied from: U(7:8,i,j,k,iElem) = U(7:8,i,j,k,iElem) * fDamping
!U2 = U2 * fDamping

! 2.) DEBUGPML: apply the damping factor only to PML variables for Phi_E and Phi_B
!               to prevent charge-related instabilities (accumulation of divergence compensation over time)
U2(19:24,:,:,:,:) = fDamping* U2(19:24,:,:,:,:) 

END SUBROUTINE PMLTimeDerivative


SUBROUTINE SetPMLdampingProfile()
!===================================================================================================================================
! Determine the local PML damping factor in x,y and z-direction using a constant/linear/polynomial/... function
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Mesh,          ONLY: GetMeshMinMaxBoundaries
USE MOD_Mesh_Vars,     ONLY: Elem_xGP,xyzMinMax
USE MOD_PML_Vars,      ONLY: PMLzeta,PMLzetaEff,PMLalpha,usePMLMinMax,xyzPMLzetaShapeOrigin,xyzPMLMinMax
USE MOD_PML_Vars,      ONLY: nPMLElems,PMLToElem,PMLprintInfoProcs
USE MOD_PML_Vars,      ONLY: PMLzeta0,PMLalpha0,xyzPhysicalMinMax,PMLzetaShape
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: i,j,k,iPMLElem
REAL                :: XiN
REAL                :: function_type
INTEGER             :: iDir,PMLDir
REAL                :: xMin,xMax
!===================================================================================================================================
!ALLOCATE(PMLRamp          (0:PP_N,0:PP_N,0:PP_N,1:nPMLElems))
ALLOCATE(PMLzeta      (1:3,0:PP_N,0:PP_N,0:PP_N,1:nPMLElems))
ALLOCATE(PMLzetaEff   (1:3,0:PP_N,0:PP_N,0:PP_N,1:nPMLElems))
ALLOCATE(PMLalpha     (1:3,0:PP_N,0:PP_N,0:PP_N,1:nPMLElems))
PMLzeta=0.
!PMLRamp=1. ! goes from 1 to 0
PMLzetaEff=0.
PMLalpha=PMLalpha0 ! currently only constant a alpha distribution in the PML region is used

! get xyzMinMax
CALL GetMeshMinMaxBoundaries()

#ifdef MPI
DO I=0,PMLprintInfoProcs-1
  IF(I.EQ.myrank)THEN
#endif /*MPI*/
  SWRITE(UNIT_stdOut,'(A,I10,A,E25.14E3,E25.14E3)') 'myrank=',I,'          xyzMinMax - X',xyzMinMax(1),xyzMinMax(2)
  SWRITE(UNIT_stdOut,'(A,I10,A,E25.14E3,E25.14E3)') 'myrank=',I,'          xyzMinMax - Y',xyzMinMax(3),xyzMinMax(4)
  SWRITE(UNIT_stdOut,'(A,I10,A,E25.14E3,E25.14E3)') 'myrank=',I,'          xyzMinMax - Z',xyzMinMax(5),xyzMinMax(6)
#ifdef MPI
  END IF
  CALL MPI_BARRIER(MPI_COMM_WORLD, iError)
END DO
#endif /*MPI*/

#ifdef MPI
DO I=0,PMLprintInfoProcs-1
  IF(I.EQ.myrank)THEN
#endif /*MPI*/
  SWRITE(UNIT_stdOut,'(A,I10,A,E25.14E3,E25.14E3)') 'myrank=',I,'  xyzPhysicalMinMax - X',xyzPhysicalMinMax(1),xyzPhysicalMinMax(2)
  SWRITE(UNIT_stdOut,'(A,I10,A,E25.14E3,E25.14E3)') 'myrank=',I,'  xyzPhysicalMinMax - Y',xyzPhysicalMinMax(3),xyzPhysicalMinMax(4)
  SWRITE(UNIT_stdOut,'(A,I10,A,E25.14E3,E25.14E3)') 'myrank=',I,'  xyzPhysicalMinMax - Z',xyzPhysicalMinMax(5),xyzPhysicalMinMax(6)
#ifdef MPI
  END IF
  CALL MPI_BARRIER(MPI_COMM_WORLD, iError)
END DO
#endif /*MPI*/

!determine PMLzeta values for each interpolation point according to ramping function (const., linear, sinusoidal, polynomial)
IF(usePMLMinMax)THEN ! use xyPMLMinMax -> define the PML region
  ! --------------------------------------------------------------------------------------------------------------------------------
  ! CURRENTLY ONLY SUPPORTS ONE DIRECTION, EITHER X- Y- or Z-DIRECTION
  ! --------------------------------------------------------------------------------------------------------------------------------
  ! the PML ramp is oriented via "xyzPMLzetaShapeOrigin" which is used as the origin for defining a rising of declining slope 
  ! of the PML ramping profile: below are two examples with a linear profile where the PML region is defined by the same values
  ! the only differens is that the origin "xyzPMLzetaShapeOrigin" located at "P(x_PML)" in the two examples is moved in the domain
  ! to a larger x-value (in this example)
  !
  !                     /                        \                                              !
  !   example 1        /                          \       example 2                             !
  !                   /                            \                                            !
  !                  /                              \                                           !
  !     origin      /  PML                      PML  \    origin                                !
  !                /  ramp                      ramp  \                                         !
  !    P(x_PML)   /                                    \    P(x_PML)                            !
  !              /                                      \                                       !
  !  ___________/                                        \___________                           !
  !                                                                                             !
  !  ---------------------->                     ---------------------->                        !
  !      x_PML              x                                 x_PML      x                      !
  !                                                                                             !
  ! --------------------------------------------------------------------------------------------------------------------------------
  DO iDir=1,3 !1=x, 2=y, 3=z
    IF((xyzPMLzetaShapeOrigin(iDir).GT.xyzPMLMinMax(2*iDir-1)).AND.(xyzPMLzetaShapeOrigin(iDir).LT.xyzPMLMinMax(2*iDir)))THEN
      IF(iDir.LT.3) CYCLE ! if all directions are true, the the point must be indisde the region
    ELSE
      PMLDir=iDir
      EXIT ! if one direction is outside, the point must be outside of the region
    END IF
    SWRITE(UNIT_stdOut,'(E25.14E3,E25.14E3,E25.14E3)') xyzPMLzetaShapeOrigin(1),xyzPMLzetaShapeOrigin(2),xyzPMLzetaShapeOrigin(3)
    CALL abort(&
    __STAMP__&
    ,'The origin reference point "xyzPMLzetaShapeOrigin" cannot lie within the PML region defined by "xyzPMLMinMax"')
  END DO
    
  ! set new values for minimum and maximum to the domain boundary values
  xyzPMLMinMax(2*PMLDir-1) = MAX(xyzPMLMinMax(2*PMLDir-1),xyzMinMax(2*PMLDir-1)) ! minimum
  xyzPMLMinMax(2*PMLDir  ) = MIN(xyzPMLMinMax(2*PMLDir  ),xyzMinMax(2*PMLDir  )) ! maximum
  SWRITE(UNIT_stdOut,'(A,I2)') 'Setting xyzPMLMinMax to <=xyzMinMax for iDir=',PMLDir
  DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
      IF((Elem_xGP(PMLDir,i,j,k,PMLToElem(iPMLElem)).GE.xyzPMLMinMax(2*PMLDir-1)).AND.&
         (Elem_xGP(PMLDir,i,j,k,PMLToElem(iPMLElem)).LE.xyzPMLMinMax(2*PMLDir)))THEN ! point is in [PMLDir]-direction region
        xMin = xyzPMLMinMax(2*PMLDir-1)-xyzPMLzetaShapeOrigin(PMLDir)               ! min of region defined for PML region
        xMax = xyzPMLMinMax(2*PMLDir  )-xyzPMLzetaShapeOrigin(PMLDir)               ! max of region defined for PML region
        PMLzeta(PMLDir,i,j,k,iPMLElem) = PMLzeta0*function_type(&
                                       ( Elem_xGP(PMLDir,i,j,k,PMLToElem(iPMLElem))-xyzPMLzetaShapeOrigin(PMLDir)-MIN(xMin,xMax) )/&
                                       ( MAX(xMin,xMax)                                                          -MIN(xMin,xMax) ),&
                                       PMLzetashape)
      END IF
  END DO; END DO; END DO; END DO !iPMLElem,k,j,i
! ----------------------------------------------------------------------------------------------------------------------------------
ELSE ! use xyzPhysicalMinMax -> define the physical region
  DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
    DO iDir=1,3 !1=x, 2=y, 3=z
      IF          (Elem_xGP(iDir,i,j,k,PMLToElem(iPMLElem)) .LT.   xyzPhysicalMinMax(2*iDir-1)) THEN ! region is in lower part
        XiN = (ABS(Elem_xGP(iDir,i,j,k,PMLToElem(iPMLElem))) - ABS(xyzPhysicalMinMax(2*iDir-1)))/&   ! of the domain
              (ABS(xyzMinMax(2*iDir-1))                      - ABS(xyzPhysicalMinMax(2*iDir-1)))
                    PMLzeta(iDir,i,j,k,iPMLElem)   = PMLzeta0*function_type(XiN,PMLzetaShape)
      ELSEIF      (Elem_xGP(iDir,i,j,k,PMLToElem(iPMLElem)) .GT.   xyzPhysicalMinMax(2*iDir)) THEN ! region is in upper part
        XiN = (ABS(Elem_xGP(iDir,i,j,k,PMLToElem(iPMLElem))) - ABS(xyzPhysicalMinMax(2*iDir)))/&   ! of the domain
              (ABS(xyzMinMax(2*iDir))                        - ABS(xyzPhysicalMinMax(2*iDir)))
                    PMLzeta(iDir,i,j,k,iPMLElem)   = PMLzeta0*function_type(XiN,PMLzetaShape)
      END IF
    END DO
  END DO; END DO; END DO; END DO !iElem,k,j,i

!    FIX this   ! determine Elem_xGP distance to PML interface for PMLRamp
!    FIX this   DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N
!    FIX this     ! x-PML region
!    FIX this     x = Elem_xGP(1,j,k,PMLToElem(iPMLElem))
!    FIX this     y = Elem_xGP(2,j,k,PMLToElem(iPMLElem))
!    FIX this     delta=0.
!    FIX this     ! x-PML region --------------------------------------------------------------
!    FIX this     IF (x .LT. xyzPhysicalMinMax(1)) THEN
!    FIX this       xi                  = ABS(x)          -ABS(xyzPhysicalMinMax(1))
!    FIX this       L                   = ABS(xyzMinMax(1))-ABS(xyzPhysicalMinMax(1))
!    FIX this     ELSEIF (x .GT. xyzPhysicalMinMax(2)) THEN
!    FIX this       xi                  = ABS(x)          -ABS(xyzPhysicalMinMax(2))
!    FIX this       L                   = ABS(xyzMinMax(2))-ABS(xyzPhysicalMinMax(2))
!    FIX this     ELSE
!    FIX this       xi=0
!    FIX this       L=1
!    FIX this     END IF
!    FIX this     delta(1)=MAXVAL((/0.,xi/L/))
!    FIX this     ! y-PML region --------------------------------------------------------------
!    FIX this     IF (y .LT. xyzPhysicalMinMax(3)) THEN
!    FIX this       xi                  = ABS(y)          -ABS(xyzPhysicalMinMax(3))
!    FIX this       L                   = ABS(xyzMinMax(3))-ABS(xyzPhysicalMinMax(3))
!    FIX this     ELSEIF (y .GT. xyzPhysicalMinMax(4)) THEN
!    FIX this       xi                  = ABS(y)          -ABS(xyzPhysicalMinMax(4))
!    FIX this       L                   = ABS(xyzMinMax(4))-ABS(xyzPhysicalMinMax(4))
!    FIX this     ELSE
!    FIX this       xi=0
!    FIX this       L=1
!    FIX this     END IF
!    FIX this     delta(2)=MAXVAL((/0.,xi/L/))
!    FIX this     ! set the ramp value from 1 down to 0: use the larged value of "delta"
!    FIX this     PMLRamp(j,k,iPMLElem) = 1. - function_type(MAXVAL(delta),PMLzetaShape)
!    FIX this   END DO; END DO; END DO !iPMLElem,k,j
END IF ! usePMLMinMax
! ----------------------------------------------------------------------------------------------------------------------------------
! CFS-PML formulation: calculate zeta eff using the complex frequency shift PMLalpha
DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
  PMLzetaEff(:,i,j,k,iPMLElem) = ( PMLalpha(:,i,j,k,iPMLElem)+PMLzeta(:,i,j,k,iPMLElem) )
END DO; END DO; END DO; END DO !iPMLElem,k,j,i
DEALLOCATE(PMLalpha)












! OLD!!!!!!!!!!!!!!!!!!
!===================================================================================================================================
! Modification to zeta values
!===================================================================================================================================
!PMLzetaNorm=.TRUE.
! Normalizing: recalculate zeta if multiple direction
!       IF (PMLzetaNorm) THEN
!         DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
!               zetaVecABS=SQRT(PMLzeta(1,i,j,k,iPMLElem)**2 &
!                              +PMLzeta(2,i,j,k,iPMLElem)**2 &
!                              +PMLzeta(3,i,j,k,iPMLElem)**2 )
!               zetaVec=MAX(PMLzeta(1,i,j,k,iPMLElem),0.)
!               zetaVec=MAX(PMLzeta(2,i,j,k,iPMLElem),zetaVec)
!               zetaVec=MAX(PMLzeta(3,i,j,k,iPMLElem),zetaVec)
!               PMLzeta(:,i,j,k,iPMLElem) = PMLzeta(:,i,j,k,iPMLElem)/zetaVecABS*zetaVec
!         END DO; END DO; END DO; END DO !iPMLElem,k,i,j
!       END IF



!===================================================================================================================================
! determine Elem_xGP distance to PML interface for PMLRamp
!===================================================================================================================================
!         !DO iPMLElem=1,nPMLElems; DO p=0,PP_N; DO q=0,PP_N
!         DO iPMLElem=1,nPMLElems; DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
!           ! x-PML region
!           !x = Face_xGP(1,p,q,PMLToFace(iPMLFace))
!           !y = Face_xGP(2,p,q,PMLToFace(iPMLFace))
!           !z = Face_xGP(3,p,q,PMLToFace(iPMLFace))
!           x = Elem_xGP(1,i,j,k,PMLToElem(iPMLElem))
!           y = Elem_xGP(2,i,j,k,PMLToElem(iPMLElem))
!           z = Elem_xGP(3,i,j,k,PMLToElem(iPMLElem))
!           delta=0.
!         
!           ! x-PML region
!           IF (x .LT. xyzPhysicalMinMax(1)) THEN
!             xi                  = ABS(x)-ABS(xyzPhysicalMinMax(1))
!             L                   = ABS(xyzMinMax(1))-ABS(xyzPhysicalMinMax(1))
!           ELSEIF (x .GT. xyzPhysicalMinMax(2)) THEN
!             xi                  = ABS(x)-ABS(xyzPhysicalMinMax(2))
!             L                   = ABS(xyzMinMax(2))-ABS(xyzPhysicalMinMax(2))
!           ELSE
!             xi=0
!             L=1
!           END IF
!           delta(1)=MAXVAL((/0.,xi/L/))
!           ! y-PML region
!           IF (y .LT. xyzPhysicalMinMax(3)) THEN
!             xi                  = ABS(y)-ABS(xyzPhysicalMinMax(3))
!             L                   = ABS(xyzMinMax(3))-ABS(xyzPhysicalMinMax(3))
!           ELSEIF (y .GT. xyzPhysicalMinMax(4)) THEN
!             xi                  = ABS(y)-ABS(xyzPhysicalMinMax(4))
!             L                   = ABS(xyzMinMax(4))-ABS(xyzPhysicalMinMax(4))
!           ELSE
!             xi=0
!             L=1
!           END IF
!           delta(2)=MAXVAL((/0.,xi/L/))
!           ! x-PML region
!           IF (z .LT. xyzPhysicalMinMax(5)) THEN
!             xi                  = ABS(z)-ABS(xyzPhysicalMinMax(5))
!             L                   = ABS(xyzMinMax(5))-ABS(xyzPhysicalMinMax(5))
!           ELSEIF (z .GT. xyzPhysicalMinMax(6)) THEN
!             xi                  = ABS(z)-ABS(xyzPhysicalMinMax(6))
!             L                   = ABS(xyzMinMax(6))-ABS(xyzPhysicalMinMax(6))
!           ELSE
!             xi=0
!             L=1
!           END IF
!           delta(3)=MAXVAL((/0.,xi/L/))
!           ! set the ramp value from 1 down to 0
!           !PMLRamp(p,q,iPMLFace)=1.-( MAXVAL(delta)-SIN(2*ACOS(-1.)*MAXVAL(delta))/(2*ACOS(-1.)) )
!           PMLRamp(i,j,k,iPMLElem) = 1. - fLinear(MAXVAL(delta))
!         
!           ! set the ramp value from 1 down to 0.82 (measured power loss)
!           ! add ramp from 0 to 0.82 (power drain 30GHz Gyrotron over 2mm PML)
!           !PMLRamp(i,j,k,iPMLElem) = PMLRamp(i,j,k,iPMLElem) + 0.82*fLinear(MAXVAL(delta))
!         !END DO; END DO; END DO !iFace,p,q
!         END DO; END DO; END DO; END DO !iPMLElem,k,i,j

END SUBROUTINE SetPMLdampingProfile


SUBROUTINE FinalizePML()
!===================================================================================================================================
!  
!===================================================================================================================================
! MODULES
USE MOD_PML_Vars,            ONLY: PMLzeta,U2,U2t
USE MOD_PML_Vars,            ONLY: ElemToPML,PMLToElem,DoPML,isPMLElem,isPMLFace,PMLToFace,FaceToPML
USE MOD_PML_Vars,            ONLY: PMLRamp,PMLInterToFace,FaceToPMLInter,isPMLInterFace
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
!RETURN
IF(.NOT.DoPML) RETURN
SDEALLOCATE(PMLzeta)
SDEALLOCATE(U2)
SDEALLOCATE(U2t)
SDEALLOCATE(PMLToElem)
SDEALLOCATE(ElemToPML)
SDEALLOCATE(PMLToFace)
SDEALLOCATE(FaceToPML)
SDEALLOCATE(PMLRamp)
SDEALLOCATE(isPMLElem)
SDEALLOCATE(isPMLFace)
SDEALLOCATE(isPMLInterFace)
SDEALLOCATE(FaceToPMLInter)
SDEALLOCATE(PMLInterToFace)
END SUBROUTINE FinalizePML


! SUBROUTINE ProlongToFace_PMLInfo(isElem,isFace_Master,isFace_Slave,doMPISides)
! !===================================================================================================================================
! ! Interpolates the interior volume data (stored at the Gauss or Gauss-Lobatto points) to the surface
! ! integration points, using fast 1D Interpolation and store in global side structure
! !===================================================================================================================================
! ! MODULES
! USE MOD_Globals
! USE MOD_PreProc
! USE MOD_Mesh_Vars,          ONLY: SideToElem,nSides
! USE MOD_Mesh_Vars,          ONLY: nBCSides,nInnerSides,nMPISides_MINE,nMPISides_YOUR
! ! IMPLICIT VARIABLE HANDLING
! IMPLICIT NONE
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! INPUT VARIABLES
! LOGICAL,INTENT(IN)              :: doMPISides  != .TRUE. only YOUR MPISides are filled, =.FALSE. BCSides +InnerSides +MPISides MINE 
! LOGICAL,INTENT(IN)              :: isElem(1:PP_nElems) 
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! OUTPUT VARIABLES
! REAL,INTENT(INOUT)              :: isFace_Master(1,0:PP_N,0:PP_N,1:nSides)
! REAL,INTENT(INOUT)              :: isFace_Slave( 1,0:PP_N,0:PP_N,1:nSides)
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! LOCAL VARIABLES 
! INTEGER                         :: i,ElemID(2),SideID,flip(2),LocSideID(2),firstSideID,lastSideID
! !===================================================================================================================================
! IF(doMPISides)THEN
!   ! only YOUR MPI Sides are filled
!   firstSideID = nBCSides+nInnerSides+nMPISides_MINE+1
!   lastSideID  = firstSideID-1+nMPISides_YOUR 
!   flip(1)     = -1
! ELSE
!   ! BCSides, InnerSides and MINE MPISides are filled
!   firstSideID = 1
!   lastSideID  = nBCSides+nInnerSides+nMPISides_MINE
!   flip(1)     = 0
! END IF
! DO SideID=firstSideID,lastSideID
!   ! master side, flip=0
!   ElemID(1)    = SideToElem(S2E_ELEM_ID,SideID)  
!   locSideID(1) = SideToElem(S2E_LOC_SIDE_ID,SideID)
!   ! neighbor side !ElemID,locSideID and flip =-1 if not existing
!   ElemID(2)    = SideToElem(S2E_NB_ELEM_ID,SideID)
!   locSideID(2) = SideToElem(S2E_NB_LOC_SIDE_ID,SideID)
!   flip(2)      = SideToElem(S2E_FLIP,SideID)
!   DO i=1,2 !first maste then slave side
!     SELECT CASE(Flip(i))
!       CASE(0) ! master side
!         isFace_Master(:,:,:,SideID)=MERGE(1,0,isElem(ElemID(i))) ! if isElem(ElemID(i))=.TRUE. -> 1, else 0
!       CASE(1:4) ! slave side
!         isFace_Slave( :,:,:,SideID)=MERGE(1,0,isElem(ElemID(i))) ! if isElem(ElemID(i))=.TRUE. -> 1, else 0
!     END SELECT
!   END DO !i=1,2, masterside & slave side 
! END DO !SideID
! END SUBROUTINE ProlongToFace_PMLInfo
END MODULE MOD_PML
























!===================================================================================================================================
! local SUBROUTINES and FUNCTIONS


REAL FUNCTION function_type(x,PMLzetaShape)
!===================================================================================================================================
! switch between different types of ramping functions for the calculation of the local zeta damping value field 
!===================================================================================================================================
! MODULES
USE MOD_Globals,       ONLY: abort
! IMPLICIT VARIABLE HANDLING 
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,    INTENT(IN) :: x
INTEGER, INTENT(IN) :: PMLzetaShape ! linear, polynomial, const., sinusoidal ramping function
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                :: fLinear,fSinus,fPolynomial
!===================================================================================================================================
SELECT CASE (PMLzetaShape)
CASE(0) !Constant Distribution of the Damping Coefficient
  function_type=1.
CASE(1) ! Linear Distribution of the Damping Coefficient
  function_type=fLinear(x)
CASE(2) ! Sinusoidal  Distribution of the Damping Coefficient
  function_type=fSinus(x)
CASE(3) ! polynomial
  function_type=fPolynomial(x)
CASE DEFAULT
  CALL abort(&
  __STAMP__&
  ,'Shape function for damping coefficient in PML region not specified!',999,999.)
END SELECT ! PMLzetaShape

END FUNCTION function_type


REAL FUNCTION fLinear(x)
!===================================================================================================================================
!  
!===================================================================================================================================
! MODULES
USE MOD_PML_Vars,            ONLY: PMLRampLength 
! IMPLICIT VARIABLE HANDLING 
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN) :: x
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL :: x_temp ![0,1] -> [0,1] sinusodial distribution
!===================================================================================================================================
IF (x.LE.PMLRampLength) THEN
  x_temp = x/PMLRampLength
  fLinear = x_temp
ELSE
  fLinear = 1.
END IF
END FUNCTION fLinear


REAL FUNCTION fSinus(x)
!===================================================================================================================================
!  
!===================================================================================================================================
! MODULES
USE MOD_PML_Vars,            ONLY: PMLRampLength
! IMPLICIT VARIABLE HANDLING 
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN) :: x
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL :: x_temp ![0,1] -> [0,1] sinusodial distribution
!===================================================================================================================================
IF (x.LE.PMLRampLength) THEN
  x_temp = x/PMLRampLength
  fSinus = x_temp-SIN(2*ACOS(-1.)*x_temp)/(2*ACOS(-1.))
ELSE
  fSinus = 1.
END IF
END FUNCTION fSinus



REAL FUNCTION fPolynomial(x)
!===================================================================================================================================
!  
!===================================================================================================================================
! MODULES
USE MOD_PML_Vars,            ONLY: PMLRampLength
! IMPLICIT VARIABLE HANDLING 
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN) :: x
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL :: x_temp ![0,1] -> [0,1] sinusodial distribution
!===================================================================================================================================
IF (x.LE.PMLRampLength) THEN
  x_temp = x/PMLRampLength
  fPolynomial = -3*x_temp**4+4*x_temp**3
ELSE
  fPolynomial = 1.
END IF
END FUNCTION fPolynomial



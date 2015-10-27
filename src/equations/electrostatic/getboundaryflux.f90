#include "boltzplatz.h"

MODULE MOD_GetBoundaryFlux
!===================================================================================================================================
! Contains FillBoundary (which depends on the considered equation)
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------

! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE GetBoundaryFlux
  MODULE PROCEDURE GetBoundaryFlux
END INTERFACE

INTERFACE InitBC
  MODULE PROCEDURE InitBC
END INTERFACE

INTERFACE FinalizeBC
  MODULE PROCEDURE FinalizeBC
END INTERFACE

PUBLIC::GetBoundaryFlux
PUBLIC:: InitBC,FinalizeBC
!===================================================================================================================================

CONTAINS


SUBROUTINE InitBC()
!===================================================================================================================================
! Initialize boundary conditions
!===================================================================================================================================
! MODULES
USE MOD_Preproc
USE MOD_Globals
USE MOD_Equation_Vars     ,ONLY: EquationInitIsDone
USE MOD_Equation_Vars     ,ONLY: BCData,nBCByType,BCSideID!,nRefstate
USE MOD_Equation_Vars     ,ONLY: BCStateFile
USE MOD_Interpolation_Vars,ONLY: InterpolationInitIsDone
USE MOD_Mesh_Vars         ,ONLY: MeshInitIsDone,nBCSides,BC,BoundaryType,nBCs
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER :: i,iSide
INTEGER :: locType,locState
INTEGER :: MaxBCState,MaxBCStateGlobal
!===================================================================================================================================
IF((.NOT.InterpolationInitIsDone).AND.(.NOT.MeshInitIsDone).AND.(.NOT.EquationInitIsDone))THEN
   CALL abort(__STAMP__,&
     "InitBC not ready to be called or already called.")
END IF
! determine globally max MaxBCState
MaxBCState = 0
DO iSide=1,nBCSides
  locType =BoundaryType(BC(iSide),BC_TYPE)
  locState=BoundaryType(BC(iSide),BC_STATE)
  ! should not be required || example for MaxBCState
  !IF((locType.NE.22).AND.locType.NE.3) MaxBCState = MAX(MaxBCState,locState)
  !IF((locType.EQ.4).AND.(locState.LT.1))&
  !  CALL abort(__STAMP__,&
  !             'No temperature (refstate) defined for BC_TYPE',locType)
  !IF((locType.EQ.23).AND.(locState.LT.1))&
  !  CALL abort(__STAMP__,&
  !             'No outflow Mach number in refstate (x,Ma,x,x,x) defined for BC_TYPE',locType)
  !IF((locType.EQ.24).AND.(locState.LT.1))&
  !  CALL abort(__STAMP__,&
  !             'No outflow pressure in refstate defined for BC_TYPE',locType)
  !IF((locType.EQ.25).AND.(locState.LT.1))&
  !  CALL abort(__STAMP__,&
  !             'No outflow pressure in refstate defined for BC_TYPE',locType)
  !IF((locType.EQ.27).AND.(locState.LT.1))&
  !  CALL abort(__STAMP__,&
  !             'No inflow refstate (dens,v1,v2,v3,pressure) in refstate defined for BC_TYPE',locType)
END DO
MaxBCStateGLobal=MaxBCState
#ifdef MPI
CALL MPI_ALLREDUCE(MPI_IN_PLACE,MaxBCStateGlobal,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,iError)
#endif /*MPI*/

! Sanity check for BCs
!IF(MaxBCState.GT.nRefState)&
!  CALL abort(__STAMP__,&
!    'ERROR: Boundary RefState not defined! (MaxBCState,nRefState):',MaxBCState,REAL(nRefState))


! Initialize State File Boundary condition
DO i=1,nBCs
  locType =BoundaryType(i,BC_TYPE)
  IF(locType.EQ.20)THEN
    ! Allocate buffer array to store temp data for all BC sides
    ALLOCATE(BCData(PP_nVar,0:PP_N,0:PP_N,nBCSides))
    BCData=0.
    CALL ReadBCFlow(BCStateFile)
    !CALL abort(__STAMP__,&
    !     'no BC defined in maxwell/getboundaryflux.f90!')
    EXIT    
  END IF
END DO

! Count number of sides of each boundary
ALLOCATE(nBCByType(nBCs))
nBCByType=0
DO iSide=1,nBCSides
  DO i=1,nBCs
    IF(BC(iSide).EQ.i) nBCByType(i)=nBCByType(i)+1
  END DO
END DO

! Sort BCs by type, store SideIDs
ALLOCATE(BCSideID(nBCs,MAXVAL(nBCByType)))
nBCByType=0
DO iSide=1,nBCSides
  DO i=1,nBCs
    IF(BC(iSide).EQ.i)THEN
      nBCByType(i)=nBCByType(i)+1
      BCSideID(i,nBCByType(i))=iSide
    END IF
  END DO
END DO

END SUBROUTINE InitBC


SUBROUTINE GetBoundaryFlux(t,tDeriv, Flux, U_Minus, NormVec, TangVec1, TangVec2, BCFace_xGP)
!===================================================================================================================================
! Computes the boundary values for a given Cartesian mesh face (defined by FaceID)
! BCType: 1...periodic, 2...exact BC
! Attention 1: this is only a tensor of local values U_Face and has to be stored into the right U_Left or U_Right in
!              SUBROUTINE CalcSurfInt
! Attention 2: U_FacePeriodic is only needed in the case of periodic boundary conditions
!===================================================================================================================================
! MODULES
USE MOD_Globals,        ONLY:Abort,CROSS
USE MOD_PreProc
USE MOD_Riemann,        ONLY:Riemann
USE MOD_Equation,       ONLY:ExactFunc
USE MOD_Equation_vars,  ONLY:c,c_inv
USE MOD_Mesh_Vars    ,  ONLY:nBCSides,nBCs,BoundaryType
USE MOD_Equation_Vars,  ONLY:nBCByType,BCSideID
USE MOD_Equation_Vars,  ONLY:BCData,nBCByType,BCSideID
USE MOD_Equation_Vars,  ONLY:IniExactFunc! richtig with particles???
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)                      :: t
INTEGER,INTENT(IN)                   :: tDeriv
REAL,INTENT(IN)                      :: U_Minus(     PP_nVar,0:PP_N,0:PP_N,1:nBCSides)
REAL,INTENT(IN)                      :: NormVec(           3,0:PP_N,0:PP_N,1:nBCSides)
REAL,INTENT(IN)                      :: TangVec1(          3,0:PP_N,0:PP_N,1:nBCSides)
REAL,INTENT(IN)                      :: TangVec2(          3,0:PP_N,0:PP_N,1:nBCSides)
REAL,INTENT(IN)                      :: BCFace_xGP(        3,0:PP_N,0:PP_N,1:nBCSides)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                     :: Flux(        PP_nVar,0:PP_N,0:PP_N,1:nBCSides)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                              :: iBC,iSide,iVar,p,q,SideID
INTEGER                              :: BCType,BCState,nBCLoc
REAL                                 :: resul(PP_nVar),epsBC
REAL                                 :: U_Face_loc(PP_nVar,0:PP_N,0:PP_N)
!===================================================================================================================================

DO iBC=1,nBCs
  IF(nBCByType(iBC).LE.0) CYCLE
  BCType =BoundaryType(iBC,BC_TYPE)
  BCState=BoundaryType(iBC,BC_STATE)
  nBCLoc =nBCByType(iBC)
  SELECT CASE(BCType)
  CASE(1) !Periodic already filled!

  CASE(2) ! exact BC = Dirichlet BC !!
    DO iSide=1,nBCLoc
      SideID=BCSideID(iBC,iSide)
      DO q=0,PP_N
        DO p=0,PP_N
          CALL ExactFunc(BCState,t,tDeriv,BCFace_xGP(:,p,q,SideID),U_Face_loc(:,p,q))
        END DO ! p
      END DO ! q
      ! Dirichlet means that we use the gradients from inside the grid cell
       CALL Riemann(Flux(:,:,:,SideID),U_Minus(:,:,:,SideID),U_Face_loc(  :,:,:), NormVec(:,:,:,SideID))
   END DO

  CASE(3) ! 1st order absorbing BC
    U_Face_loc=0.
    DO iSide=1,nBCLoc
      SideID=BCSideID(iBC,iSide)
      CALL Riemann(Flux(:,:,:,SideID),U_Minus(:,:,:,SideID),U_Face_loc(:,:,:),NormVec(:,:,:,SideID))
    END DO
  
  CASE(4) ! perfectly conducting surface (MunzOmnesSchneider 2000, pp. 97-98)
    ! Determine the exact BC state
   DO iSide=1,nBCLoc
     SideID=BCSideID(iBC,iSide)
     DO q=0,PP_N
       DO p=0,PP_N
         resul=U_Minus(:,p,q,SideID)
         U_Face_loc(  4,p,q) = -resul(  4)
       END DO ! p
     END DO ! q
     ! Dirichlet means that we use the gradients from inside the grid cell
     CALL Riemann(Flux(:,:,:,SideID),U_Minus(:,:,:,SideID),U_Face_loc(:,:,:),NormVec(:,:,:,SideID))
   END DO ! iSide=1,nBCLod

  CASE(10) ! symmetry BC
    ! Determine the exact BC state
     DO iSide=1,nBCLoc
       SideID=BCSideID(iBC,iSide)
       DO q=0,PP_N
         DO p=0,PP_N
           resul=U_Minus(:,p,q,SideID)
           U_Face_loc(1:3,p,q) = -resul(1:3)
           U_Face_loc(  4,p,q) = resul(  4)
         END DO ! p
       END DO ! q
       ! Dirichlet means that we use the gradients from inside the grid cell
       CALL Riemann(Flux(:,:,:,SideID),U_Minus(:,:,:,SideID),U_Face_loc(:,:,:),NormVec(:,:,:,SideID))
     END DO ! iSide=1,nBCLod

  CASE(20) ! exact BC = Dirichlet BC !!
    ! SPECIAL BC: BCState uses readin state
    DO iSide=1,nBCLoc
      SideID=BCSideID(iBC,iSide)
      ! Dirichlet means that we use the gradients from inside the grid cell
      CALL Riemann(Flux(:,:,:,SideID),U_Minus( :,:,:,SideID),BCData(:,:,:,SideID),NormVec(:,:,:,SideID))
    END DO
  
  CASE DEFAULT ! unknown BCType
    CALL abort(__STAMP__,&
         'no BC defined in maxwell/getboundaryflux.f90!')
  END SELECT ! BCType
END DO ! iBC=1,nBC

END SUBROUTINE GetBoundaryFlux


SUBROUTINE FinalizeBC()
!===================================================================================================================================
! Initialize boundary conditions
!===================================================================================================================================
! MODULES
USE MOD_Equation_Vars,ONLY: BCData,nBCByType,BCSideID
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(BCData)
SDEALLOCATE(nBCByType)
SDEALLOCATE(BCSideID)
END SUBROUTINE FinalizeBC



SUBROUTINE ReadBCFlow(FileName)
!===================================================================================================================================
! Get parameters used for the sponge region
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Equation_Vars,      ONLY:BCData
USE MOD_Mesh_Vars,          ONLY:offsetElem
USE MOD_HDF5_input,         ONLY:OpenDataFile,GetDataProps,CloseDataFile,ReadAttribute,ReadArray
USE MOD_Basis,              ONLY:LegendreGaussNodesAndWeights,LegGaussLobNodesAndWeights
USE MOD_Basis,              ONLY:BarycentricWeights,InitializeVandermonde
USE MOD_Interpolation_Vars, ONLY:xGP
USE MOD_ChangeBasis,        ONLY:ChangeBasis3D
USE MOD_ProlongToFace,      ONLY:ProlongToFace_BC
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN) :: FileName
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,ALLOCATABLE   :: U_local(:,:,:,:,:),U_N(:,:,:,:,:)
REAL,ALLOCATABLE   :: Vdm_NHDF5_N(:,:)
INTEGER            :: iElem,nVar_HDF5,N_HDF5,nElems_HDF5
CHARACTER(LEN=255) :: NodeType_HDF5
LOGICAL            :: InterpolateSolution
REAL,ALLOCATABLE   :: xGP_tmp(:),wBary_tmp(:),wGP_tmp(:)
!===================================================================================================================================
SWRITE(UNIT_StdOut,'(A,A)')'  Read BC state from file "',FileName
CALL OpenDataFile(FileName,create=.FALSE.,single=.FALSE.)
CALL GetDataProps(nVar_HDF5,N_HDF5,nELems_HDF5,NodeType_HDF5)
IF(((N_HDF5.NE.PP_N) .OR. (TRIM(NodeType_HDF5).NE.TRIM(NodeType))))THEN
  InterpolateSolution=.TRUE.
ELSE
  InterpolateSolution=.FALSE.
END IF

!temporal array for extrapolation to boundary
ALLOCATE(U_N(PP_nVar,0:PP_N,0:PP_N,0:PP_N,PP_nElems))

! Read in state
IF(.NOT. InterpolateSolution)THEN
  ! No interpolation needed, read solution directly from file
  CALL ReadArray('DG_Solution',5,(/PP_nVar,PP_N+1,PP_N+1,PP_N+1,PP_nElems/),OffsetElem,5,RealArray=U_N)
  ! read additional data (e.g. indicators etc)                                                
ELSE
  SWRITE(UNIT_stdOut,'(A)')' Interpolating BC-state...'
  ! We need to interpolate the solution to the new computational grid
  ALLOCATE(Vdm_NHDF5_N(0:PP_N,0:N_HDF5)         &
          , wGP_tmp(0:N_HDF5)                   &
          , xGP_tmp(0:N_HDF5)                   &
          , wBary_tmp(0:N_HDF5)                 )


  SELECT CASE(TRIM(NodeType_HDF5))
  CASE("GAUSS")
    CALL LegendreGaussNodesAndWeights(N_HDF5,xGP_tmp,wGP_tmp)
  CASE("GAUSS-LOBATTO")
    CALL LegGaussLobNodesAndWeights(N_HDF5,xGP_tmp,wGP_tmp)
  CASE DEFAULT
    CALL abort(__STAMP__,&
        ' Not type of BackGround-Field is not implemented!')
  END SELECT
  CALL BarycentricWeights(N_HDF5,xGP_tmp,wBary_tmp)
  CALL InitializeVandermonde(N_HDF5,PP_N,wBary_tmp,xGP_tmp,xGP,Vdm_NHDF5_N)

  ALLOCATE(U_local(PP_nVar,0:N_HDF5,0:N_HDF5,0:N_HDF5,PP_nElems))
  CALL ReadArray('DG_Solution',5,(/PP_nVar,N_HDF5+1,N_HDF5+1,N_HDF5+1,PP_nElems/),OffsetElem,5,RealArray=U_local)
  SWRITE(UNIT_stdOut,*)'Interpolating base flow from restart grid with N=',N_HDF5,' to computational grid with N=',PP_N
  DO iElem=1,PP_nElems
    CALL ChangeBasis3D(PP_nVar,N_HDF5,PP_N,Vdm_NHDF5_N,U_local(:,:,:,:,iElem),U_N(:,:,:,:,iElem))
  END DO
  !DEALLOCATE(U_local,Vdm_NHDF5_N)
END IF
CALL CloseDataFile() 

SWRITE(UNIT_stdOut,'(A)')'  Interpolating the BC flow on the BC sides...'
CALL ProlongToFace_BC(U_N,BCData)
DEALLOCATE(U_N)

SWRITE(UNIT_stdOut,'(A)')'  done initializing BC state!'
END SUBROUTINE ReadBCFlow


END MODULE MOD_GetBoundaryFlux

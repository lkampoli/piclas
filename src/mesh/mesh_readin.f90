!==================================================================================================================================
! Copyright (c) 2010 - 2018 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
!
! This file is part of PICLas (gitlab.com/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

MODULE MOD_Mesh_ReadIn
!===================================================================================================================================
!> \brief Module containing routines to read the mesh and BCs from a HDF5 file
!>
!> This module contains the following routines related to mesh IO
!> - parallel HDF5-based mesh IO
!> - readin of mesh coordinates and connectivity
!> - readin of boundary conditions
!===================================================================================================================================
! MODULES
USE MOD_HDF5_Input
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
!> @defgroup eleminfo ElemInfo parameters
!>  Named parameters for ElemInfo array in mesh file
!> @{
INTEGER,PARAMETER    :: ElemInfoSize=6        !< number of entry in each line of ElemInfo
INTEGER,PARAMETER    :: ELEM_Type=1           !< entry position,
INTEGER,PARAMETER    :: ELEM_Zone=2
INTEGER,PARAMETER    :: ELEM_FirstSideInd=3
INTEGER,PARAMETER    :: ELEM_LastSideInd=4
INTEGER,PARAMETER    :: ELEM_FirstNodeInd=5
INTEGER,PARAMETER    :: ELEM_LastNodeInd=6
!> @}

!> @defgroup sideinfo SideInfo parameters
!>  Named parameters for SideInfo array in mesh file
!> @{
INTEGER,PARAMETER    :: SideInfoSize=5        !< number of entries in each line of SideInfo
INTEGER,PARAMETER    :: SIDE_Type=1
INTEGER,PARAMETER    :: SIDE_ID=2
INTEGER,PARAMETER    :: SIDE_nbElemID=3
INTEGER,PARAMETER    :: SIDE_Flip=4
INTEGER,PARAMETER    :: SIDE_BCID=5
!> @}

INTEGER,ALLOCATABLE  :: NodeInfo(:)
INTEGER,ALLOCATABLE  :: NodeMap(:)
INTEGER              :: nNodeIDs

! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE ReadMesh
  MODULE PROCEDURE ReadMesh
END INTERFACE

INTERFACE Qsort1Int
  MODULE PROCEDURE Qsort1Int
END INTERFACE

INTERFACE INVMAP
  MODULE PROCEDURE INVMAP
END INTERFACE

PUBLIC::ReadMesh,Qsort1Int,INVMAP
!===================================================================================================================================

CONTAINS

SUBROUTINE ReadBCs()
!===================================================================================================================================
!> This module will read boundary conditions from the HDF5 mesh file and from the parameter file.
!> The parameters defined in the mesh file can be overridden by those defined in the parameter file, by specifying the parameters
!> name and a new boundary condition set: a user-defined boundary condition consists of a type and a state.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Mesh_Vars   ,ONLY: BoundaryName,BoundaryType,nBCs,nUserBCs
#if USE_HDG
USE MOD_Mesh_Vars   ,ONLY: ChangedPeriodicBC
#endif /*USE_HDG*/
USE MOD_ReadInTools ,ONLY: GETINTARRAY,CountOption,GETSTR
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL,ALLOCATABLE            :: UserBCFound(:)
CHARACTER(LEN=255),ALLOCATABLE :: BCNames(:)
INTEGER, ALLOCATABLE           :: BCMapping(:),BCType(:,:)
INTEGER                        :: iBC,iUserBC
INTEGER                        :: Offset=0 ! Every process reads all BCs
!===================================================================================================================================
! read in boundary conditions from ini file, will overwrite BCs from meshfile!
nUserBCs = CountOption('BoundaryName')
IF(nUserBCs.GT.0)THEN
  ALLOCATE(BoundaryName(1:nUserBCs))
  ALLOCATE(BoundaryType(1:nUserBCs,2))
  DO iBC=1,nUserBCs
    BoundaryName(iBC)   = GETSTR('BoundaryName')
    BoundaryType(iBC,:) = GETINTARRAY('BoundaryType',2) !(/Type,State/)
  END DO
END IF !nUserBCs>0

! Read boundary names from data file
CALL GetDataSize(File_ID,'BCNames',nDims,HSize)
CHECKSAFEINT(HSize(1),4)
nBCs=INT(HSize(1),4)
DEALLOCATE(HSize)
ALLOCATE(BCNames(nBCs))
ALLOCATE(BCMapping(nBCs))
ALLOCATE(UserBCFound(nUserBCs))

! Associate construct for integer KIND=8 possibility
ASSOCIATE ( nBCs   => INT(nBCs,IK)   ,&
            Offset => INT(Offset,IK) )
  CALL ReadArray('BCNames',1,(/nBCs/),Offset,1,StrArray=BCNames)  ! Type is a dummy type only
END ASSOCIATE
! User may have redefined boundaries in the ini file. So we have to create mappings for the boundaries.
BCMapping=0
UserBCFound=.FALSE.
IF(nUserBCs .GT. 0)THEN
  DO iBC=1,nBCs
    DO iUserBC=1,nUserBCs
      IF(INDEX(TRIM(BCNames(iBC)),TRIM(BoundaryName(iUserBC))).NE.0)THEN
        BCMapping(iBC)=iUserBC
        UserBCFound(iUserBC)=.TRUE.
      END IF
    END DO
  END DO
END IF
DO iUserBC=1,nUserBCs
  IF(.NOT.UserBCFound(iUserBC)) CALL Abort(&
__STAMP__&
,'Boundary condition specified in parameter file has not been found: '//TRIM(BoundaryName(iUserBC)))
END DO
DEALLOCATE(UserBCFound)

! Read boundary types from data file
CALL GetDataSize(File_ID,'BCType',nDims,HSize)
IF((HSize(1).NE.4).OR.(HSize(2).NE.nBCs)) STOP 'Problem in readBC'
DEALLOCATE(HSize)
ALLOCATE(BCType(4,nBCs))
offset=0

! Associate construct for integer KIND=8 possibility
ASSOCIATE ( nBCs   => INT(nBCs,IK)   ,&
            Offset => INT(Offset,IK) )
  CALL ReadArray('BCType',2,(/4_IK,nBCs/),Offset,1,IntegerArray_i4=BCType)
END ASSOCIATE
! Now apply boundary mappings
#if USE_HDG
ChangedPeriodicBC=.FALSE. ! set true if BCs are changed from periodic to non-periodic
#endif /*USE_HDG*/
IF(nUserBCs .GT. 0)THEN
  DO iBC=1,nBCs
    IF(BCMapping(iBC) .NE. 0)THEN
      ! non-periodic to periodic
      IF((BoundaryType(BCMapping(iBC),1).EQ.1).AND.(BCType(1,iBC).NE.1)) CALL abort(&
          __STAMP__&
          ,'Remapping non-periodic to periodic BCs is not possible!')
#if USE_HDG
      ! periodic to non-periodic
      IF((BCType(1,iBC).EQ.1).AND.(BoundaryType(BCMapping(iBC),1).NE.1))THEN
        ChangedPeriodicBC=.TRUE.
        ! Currently, remapping periodic to non-periodic BCs is not allowed. In the future, implement nGlobalUniqueSides
        ! determination.
        CALL abort(&
        __STAMP__&
        ,'Remapping periodic to non-periodic BCs is currently not possible for HDG because this changes nGlobalUniqueSides!')
      END IF
#endif /*USE_HDG*/
      ! Output
      SWRITE(Unit_StdOut,'(A,A)')    ' |     Boundary in HDF file found |  ',TRIM(BCNames(iBC))
      SWRITE(Unit_StdOut,'(A,I8,I8)')' |                            was | ',BCType(1,iBC),BCType(3,iBC)
      SWRITE(Unit_StdOut,'(A,I8,I8)')' |                      is set to | ',BoundaryType(BCMapping(iBC),1:2)
      BCType(1,iBC) = BoundaryType(BCMapping(iBC),BC_TYPE)
      BCType(3,iBC) = BoundaryType(BCMapping(iBC),BC_STATE)
    END IF
  END DO
END IF
IF(ALLOCATED(BoundaryName)) DEALLOCATE(BoundaryName)
IF(ALLOCATED(BoundaryType)) DEALLOCATE(BoundaryType)
ALLOCATE(BoundaryName(nBCs))
ALLOCATE(BoundaryType(nBCs,3))
BoundaryName = BCNames
BoundaryType(:,BC_TYPE)  = BCType(1,:)
BoundaryType(:,BC_STATE) = BCType(3,:)
BoundaryType(:,BC_ALPHA) = BCType(4,:)
SWRITE(UNIT_StdOut,'(132("."))')
SWRITE(Unit_StdOut,'(A,A16,A20,A10,A10,A10)')'BOUNDARY CONDITIONS','|','Name','Type','State','Alpha'
DO iBC=1,nBCs
  SWRITE(*,'(A,A33,A20,I10,I10,I10)')' |','|',TRIM(BoundaryName(iBC)),BoundaryType(iBC,:)
END DO
SWRITE(UNIT_StdOut,'(132("."))')
DEALLOCATE(BCNames,BCType,BCMapping)
END SUBROUTINE ReadBCs


SUBROUTINE ReadMesh(FileString)
!===================================================================================================================================
!> This subroutine reads the mesh from the HDF5 mesh file. The connectivity and further relevant information as flips
!> (i.e. the orientation of sides towards each other) is already contained in the mesh file.
!> For parallel computations the number of elements will be distributed equally onto all processors and each processor only reads
!> its own subset of the mesh.
!> For a documentation of the mesh format see the documentation provided with HOPR (hopr-project.org)
!> The arrays ElemInfo, SideInfo and NodeCoords are read, alongside with the boundary condition data.
!> If the mesh is non-conforming and based on a tree representation, the corresponding tree data (Coords, parameter ranges,
!> connectivity) is also read in.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Mesh_Vars            ,ONLY: tElem,tSide
USE MOD_Mesh_Vars            ,ONLY: NGeo,NGeoTree
USE MOD_Mesh_Vars            ,ONLY: NodeCoords,TreeCoords
USE MOD_Mesh_Vars            ,ONLY: offsetElem,offsetTree,nElems,nGlobalElems,nTrees,nGlobalTrees,nNodes
USE MOD_Mesh_Vars            ,ONLY: xiMinMax,ElemToTree
USE MOD_Mesh_Vars            ,ONLY: nSides,nInnerSides,nBCSides,nMPISides,nAnalyzeSides,nGlobalMortarSides
USE MOD_Mesh_Vars            ,ONLY: nMortarSides,isMortarMesh
USE MOD_Mesh_Vars            ,ONLY: nGlobalUniqueSidesFromMesh
USE MOD_Mesh_Vars            ,ONLY: useCurveds
USE MOD_Mesh_Vars            ,ONLY: BoundaryType
USE MOD_Mesh_Vars            ,ONLY: MeshInitIsDone
USE MOD_Mesh_Vars            ,ONLY: Elems,Nodes
USE MOD_Mesh_Vars            ,ONLY: GETNEWELEM,GETNEWSIDE,createSides
USE MOD_IO_HDF5
#if USE_MPI
USE MOD_MPI_Vars             ,ONLY: nMPISides_Proc,nNbProcs,NbProc
USE MOD_LoadBalance_Tools    ,ONLY: DomainDecomposition
#ifdef PARTICLES
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars     ,ONLY: nDeposPerElem,nSurfacePartsPerElem
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/
USE MOD_PreProc
USE MOD_ReadInTools
USE MOD_StringTools          ,ONLY: STRICMP
#endif /*USE_MPI*/
#ifdef PARTICLES
USE MOD_LoadBalance_Vars     ,ONLY: nTracksPerElem,nPartsPerBCElem,nPartsPerElem,nSurfacefluxPerElem
USE MOD_Particle_Vars        ,ONLY: VarTimeStep
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)  :: FileString
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
TYPE(tElem),POINTER            :: aElem
TYPE(tSide),POINTER            :: aSide,bSide
REAL,ALLOCATABLE               :: NodeCoordsTmp(:,:,:,:,:)
INTEGER,ALLOCATABLE            :: ElemInfo(:,:),SideInfo(:,:)
INTEGER                        :: BCindex
INTEGER                        :: iElem,ElemID
INTEGER                        :: iNode,jNode,iNodeP,NodeID
INTEGER                        :: offsetNodeID
REAL   ,ALLOCATABLE            :: NodeCoords_indx(:,:)
INTEGER                        :: CornerNodeIDswitch(8)
INTEGER                        :: iLocSide,nbLocSide
INTEGER                        :: iSide
INTEGER                        :: FirstNodeInd,LastNodeInd,FirstSideInd,LastSideInd,FirstElemInd,LastElemInd
INTEGER                        :: nPeriodicSides,nMPIPeriodics
INTEGER                        :: ReduceData(11)
INTEGER                        :: nSideIDs,offsetSideID
INTEGER                        :: iMortar,jMortar,nMortars
#if USE_MPI
INTEGER                        :: iNbProc
INTEGER                        :: iProc
INTEGER,ALLOCATABLE            :: MPISideCount(:)
! new weight distribution method
#endif /*USE_MPI*/
LOGICAL                        :: doConnection
LOGICAL                        :: oriented
LOGICAL                        :: isMortarMeshExists
#ifdef PARTICLES
REAL, ALLOCATABLE              :: GlobVarTimeStep(:)
#endif
!===================================================================================================================================
IF(MESHInitIsDone) RETURN
IF(MPIRoot)THEN
  IF(.NOT.FILEEXISTS(FileString))  CALL abort(&
__STAMP__ &
,'readMesh from data file "'//TRIM(FileString)//'" does not exist')
END IF

SWRITE(UNIT_stdOut,'(A)')'READ MESH FROM DATA FILE "'//TRIM(FileString)//'" ...'
SWRITE(UNIT_StdOut,'(132("-"))')

! Get ElemInfo from Mesh file
CALL OpenDataFile(FileString,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)
CALL GetDataSize(File_ID,'ElemInfo',nDims,HSize)
CALL ReadAttribute(File_ID,'nUniqueSides',1,IntegerScalar=nGlobalUniqueSidesFromMesh)
CALL CloseDataFile()
CHECKSAFEINT(HSize(2),4)
nGlobalElems=INT(HSize(2),4) !global number of elements
DEALLOCATE(HSize)
IF(MPIRoot.AND.(nGlobalElems.LT.nProcessors))CALL abort(__STAMP__&
    ,' Number of elements < number of processors',nGlobalElems,REAL(nProcessors))

!----------------------------------------------------------------------------------------------------------------------------
!                              DOMAIN DECOMPOSITION
!----------------------------------------------------------------------------------------------------------------------------
#if USE_MPI
CALL DomainDecomposition()
#else /*USE_MPI*/
nElems=nGlobalElems   ! Local number of Elements
offsetElem=0          ! Offset is the index of first entry, hdf5 array starts at 0-.GT. -1
#endif /*USE_MPI*/

!----------------------------------------------------------------------------------------------------------------------------
!                              ALLOCATE element counters
!----------------------------------------------------------------------------------------------------------------------------
#ifdef PARTICLES
! Re-allocate nPartsPerElem depending on new number of elements
IF(.NOT.ALLOCATED(nPartsPerElem))THEN
  ALLOCATE(nPartsPerElem(1:nElems))
ELSE
  SDEALLOCATE(nPartsPerElem)
  ALLOCATE(nPartsPerElem(1:nElems))
END IF
nPartsPerElem=0
CALL AddToElemData(ElementOut,'nPartsPerElem',LongIntArray=nPartsPerElem(:))
#if USE_LOADBALANCE
SDEALLOCATE(nDeposPerElem)
ALLOCATE(nDeposPerElem(1:nElems))
nDeposPerElem=0
#endif /*USE_LOADBALANCE*/
SDEALLOCATE(nTracksPerElem)
ALLOCATE(nTracksPerElem(1:nElems))
nTracksPerElem=0
SDEALLOCATE(nSurfacefluxPerElem)
ALLOCATE(nSurfacefluxPerElem(1:nElems))
nSurfacefluxPerElem=0
SDEALLOCATE(nPartsPerBCElem)
ALLOCATE(nPartsPerBCElem(1:nElems))
nPartsPerBCElem=0
#if USE_LOADBALANCE
SDEALLOCATE(nSurfacePartsPerElem)
ALLOCATE(nSurfacePartsPerElem(1:nElems))
nSurfacePartsPerElem=0
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/

!----------------------------------------------------------------------------------------------------------------------------
!                              VARIABLE TIME STEP
!----------------------------------------------------------------------------------------------------------------------------
#ifdef PARTICLES
IF(VarTimeStep%UseDistribution) THEN
  IF(ALLOCATED(VarTimeStep%ElemFac)) THEN
    ALLOCATE(GlobVarTimeStep(nGlobalElems))
    GlobVarTimeStep(1:nGlobalelems) = VarTimeStep%ElemFac(1:nGlobalelems)
    ! Allocate new array for the time step distribution (going from global time step distribution to proc local with nElems)
    DEALLOCATE(VarTimeStep%ElemFac)
    ALLOCATE(VarTimeStep%ElemFac(nElems))
    ! And now get the new variable time steps for the respective elements
    VarTimeStep%ElemFac(1:nElems) = GlobVarTimeStep(offsetElem+1:offsetElem+nElems)
    ! Global distribution is not required anymore
    DEALLOCATE(GlobVarTimeStep)
  ELSE
    ! Allocate the array for the element-wise time step factor
    ALLOCATE(VarTimeStep%ElemFac(nElems))
    VarTimeStep%ElemFac = 1.0
#if USE_MPI
    ! Allocate the array for the element-wise weighting factor
    ALLOCATE(VarTimeStep%ElemWeight(nElems))
    VarTimeStep%ElemWeight = 1.0
#endif
  END IF
END IF
#endif

CALL OpenDataFile(FileString,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)
CALL readBCs()
!----------------------------------------------------------------------------------------------------------------------------
!                              ELEMENTS
!----------------------------------------------------------------------------------------------------------------------------

!read local ElemInfo from data file
FirstElemInd=offsetElem+1
LastElemInd=offsetElem+nElems
ALLOCATE(Elems(                FirstElemInd:LastElemInd))
ALLOCATE(ElemInfo(ElemInfoSize,FirstElemInd:LastElemInd))

! Associate construct for integer KIND=8 possibility
ASSOCIATE (&
      ElemInfoSize => INT(ElemInfoSize,IK) ,&
      nElems       => INT(nElems,IK)       ,&
      offsetElem   => INT(offsetElem,IK)  )
  CALL ReadArray('ElemInfo',2,(/ElemInfoSize,nElems/),offsetElem,2,IntegerArray_i4=ElemInfo)
END ASSOCIATE

DO iElem=FirstElemInd,LastElemInd
  iSide=ElemInfo(ELEM_FirstSideInd,iElem) !first index -1 in Sideinfo
  iNode=ElemInfo(ELEM_FirstNodeInd,iElem) !first index -1 in NodeInfo
  Elems(iElem)%ep=>GETNEWELEM()
  aElem=>Elems(iElem)%ep
  aElem%Ind    = iElem
  aElem%Type   = ElemInfo(ELEM_Type,iElem)
  aElem%Zone   = ElemInfo(ELEM_Zone,iElem)
END DO

!----------------------------------------------------------------------------------------------------------------------------
!                              SIDES
!----------------------------------------------------------------------------------------------------------------------------

#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_WORLD,iERROR)
#endif /*USE_MPI*/
offsetSideID=ElemInfo(ELEM_FirstSideInd,FirstElemInd) ! hdf5 array starts at 0-> -1
nSideIDs=ElemInfo(ELEM_LastSideInd,LastElemInd)-ElemInfo(ELEM_FirstSideInd,FirstElemInd)
!read local SideInfo from data file
FirstSideInd=offsetSideID+1
LastSideInd=offsetSideID+nSideIDs
ALLOCATE(SideInfo(SideInfoSize,FirstSideInd:LastSideInd))

! Associate construct for integer KIND=8 possibility
ASSOCIATE (&
      SideInfoSize   => INT(SideInfoSize,IK)   ,&
      nSideIDs       => INT(nSideIDs,IK)       ,&
      offsetSideID   => INT(offsetSideID,IK)  )
  CALL ReadArray('SideInfo',2,(/SideInfoSize,nSideIDs/),offsetSideID,2,IntegerArray_i4=SideInfo)
END ASSOCIATE

DO iElem=FirstElemInd,LastElemInd
  aElem=>Elems(iElem)%ep
  iSide=ElemInfo(ELEM_FirstSideInd,iElem) !first index -1 in Sideinfo
  !build up sides of the element according to CGNS standard
  ! assign flip
  DO iLocSide=1,6
    aSide=>aElem%Side(iLocSide)%sp
    iSide=iSide+1
    ! ALLOCATE MORTAR
    ElemID=SideInfo(SIDE_nbElemID,iSide) !IF nbElemID <0, this marks a mortar master side.
                                         ! The number (-1,-2,-3) is the Type of mortar
    IF(ElemID.LT.0)THEN ! mortar Sides attached!
      aSide%MortarType=ABS(ElemID)
      SELECT CASE(aSide%MortarType)
      CASE(1)
        aSide%nMortars=4
      CASE(2,3)
        aSide%nMortars=2
      END SELECT
      ALLOCATE(aSide%MortarSide(aSide%nMortars))
      DO iMortar=1,aSide%nMortars
        aSide%MortarSide(iMortar)%sp=>GETNEWSIDE()  !mortarType=0
      END DO
    ELSE
      aSide%nMortars=0
    END IF
    IF(SideInfo(SIDE_Type,iSide).LT.0) aSide%MortarType=-10 !marks small neighbor  side as belonging to a mortar

    IF(aSide%MortarType.LE.0)THEN
      aSide%Elem=>aElem
      oriented=(SideInfo(SIDE_ID,iSide).GT.0)
      aSide%Ind=ABS(SideInfo(SIDE_ID,iSide))
      IF(oriented)THEN !oriented side
        aSide%flip=0
#ifdef PARTICLES
        aSide%BC_Alpha=99
#endif /*PARTICLES*/
      ELSE !not oriented
        aSide%flip=MOD(Sideinfo(SIDE_Flip,iSide),10)
        IF((aSide%flip.LT.0).OR.(aSide%flip.GT.4)) STOP 'NodeID doesnt belong to side'
#ifdef PARTICLES
        aSide%BC_Alpha=-99
#endif /*PARTICLES*/
      END IF
    ELSE !mortartype>0
      DO iMortar=1,aSide%nMortars
        iSide=iSide+1
        aSide%mortarSide(iMortar)%sp%Elem=>aElem
        IF(SideInfo(SIDE_ID,iSide).LT.0) STOP 'Problem in Mortar readin,should be flip=0'
        aSide%mortarSide(iMortar)%sp%flip=0
        aSide%mortarSide(iMortar)%sp%Ind=ABS(SideInfo(SIDE_ID,iSide))
#ifdef PARTICLES
        aSide%BC_Alpha=99
#endif /*PARTICLES*/
      END DO !iMortar
    END IF
  END DO !i=1,locnSides
END DO !iElem

! build up side connection
DO iElem=FirstElemInd,LastElemInd
  aElem=>Elems(iElem)%ep
  iSide=ElemInfo(ELEM_FirstSideInd,iElem) !first index -1 in Sideinfo
  DO iLocSide=1,6
    aSide=>aElem%Side(iLocSide)%sp
    iSide=iSide+1
    ! LOOP over mortars, if no mortar, then LOOP is executed once
    nMortars=aSide%nMortars
    DO iMortar=0,nMortars
      IF(iMortar.GT.0)THEN
        iSide=iSide+1
        aSide=>aElem%Side(iLocSide)%sp%mortarSide(iMortar)%sp
      END IF
      elemID  = SideInfo(SIDE_nbElemID,iSide)
      BCindex = SideInfo(SIDE_BCID,iSide)

      doConnection=.TRUE. ! for periodic sides if BC is reassigned as non periodic
      IF(BCindex.NE.0)THEN !BC
        aSide%BCindex = BCindex
        IF((BoundaryType(aSide%BCindex,BC_TYPE).NE.1).AND.&
           (BoundaryType(aSide%BCindex,BC_TYPE).NE.100))THEN ! Reassignment from periodic to non-periodic
          doConnection=.FALSE.
          aSide%flip  =0
#ifdef PARTICLES
          aSide%BC_Alpha=0
#endif /*PARTICLES*/
          IF(iMortar.EQ.0) aSide%mortarType  = 0
          IF(iMortar.EQ.0) aSide%nMortars    = 0
          elemID            = 0
        END IF
      ELSE
        aSide%BCindex = 0
      END IF

      !no connection for mortar master
      IF(aSide%mortarType.GT.0) CYCLE
      IF(.NOT.doConnection) CYCLE
      IF(ASSOCIATED(aSide%connection)) CYCLE

      ! check if neighbor on local proc or MPI connection
      IF(elemID.NE.0)THEN !connection
        IF((elemID.LE.LastElemInd).AND.(elemID.GE.FirstElemInd))THEN !local
          !TODO: Check if this is still ok
          DO nbLocSide=1,6
            bSide=>Elems(elemID)%ep%Side(nbLocSide)%sp
            ! LOOP over mortars, if no mortar, then LOOP is executed once
            nMortars=bSide%nMortars
            DO jMortar=0,nMortars
              IF(jMortar.GT.0) bSide=>Elems(elemID)%ep%Side(nbLocSide)%sp%mortarSide(jMortar)%sp

              IF(bSide%ind.EQ.aSide%ind)THEN
                aSide%connection=>bSide
                bSide%connection=>aSide
                EXIT
              END IF !bSide%ind.EQ.aSide%ind
            END DO !jMortar
          END DO !nbLocSide
        ELSE !MPI connection
#if USE_MPI
          aSide%connection=>GETNEWSIDE()
          aSide%connection%flip=aSide%flip
          aSide%connection%Elem=>GETNEWELEM()
          aSide%NbProc = ELEMIPROC(elemID)
#else
          CALL abort(__STAMP__, &
            ' ElemID of neighbor not in global Elem list ')
#endif
        END IF
      END IF
    END DO !iMortar
  END DO !iLocSide
END DO !iElem


!----------------------------------------------------------------------------------------------------------------------------
!                              NODES
!----------------------------------------------------------------------------------------------------------------------------

!read local Node Info from data file
offsetNodeID=ElemInfo(ELEM_FirstNodeInd,FirstElemInd) ! hdf5 array starts at 0-> -1
nNodeIDs=ElemInfo(ELEM_LastNodeInd,LastElemInd)-ElemInfo(ELEM_FirstNodeInd,FirstElemind)
FirstNodeInd=offsetNodeID+1
LastNodeInd=offsetNodeID+nNodeIDs
ALLOCATE(NodeInfo(FirstNodeInd:LastNodeInd))

! Associate construct for integer KIND=8 possibility
ASSOCIATE (&
      nNodeIDs     => INT(nNodeIDs,IK)     ,&
      offsetNodeID => INT(offsetNodeID,IK) )
  CALL ReadArray('GlobalNodeIDs',1,(/nNodeIDs/),offsetNodeID,1,IntegerArray_i4=NodeInfo)
  ALLOCATE(NodeCoords_indx(3,nNodeIDs))
  CALL ReadArray('NodeCoords',2,(/3_IK,nNodeIDs/),offsetNodeID,2,RealArray=NodeCoords_indx)
END ASSOCIATE

CALL GetNodeMap() !get nNodes and local NodeMap from NodeInfo array
LOGWRITE(*,*)'MIN,MAX,SIZE of NodeMap',MINVAL(NodeMap),MAXVAL(NodeMap),SIZE(NodeMap,1)

ALLOCATE(Nodes(1:nNodes)) ! pointer list, entry is known by INVMAP(i,nNodes,NodeMap)
DO iNode=1,nNodes
  NULLIFY(Nodes(iNode)%np)
END DO
! the cornernodes are not the first 8 entries (for Ngeo>1) of nodeinfo array so mapping is build
CornerNodeIDswitch(1)=1
CornerNodeIDswitch(2)=(Ngeo+1)
CornerNodeIDswitch(3)=(Ngeo+1)**2
CornerNodeIDswitch(4)=(Ngeo+1)*Ngeo+1
CornerNodeIDswitch(5)=(Ngeo+1)**2*Ngeo+1
CornerNodeIDswitch(6)=(Ngeo+1)**2*Ngeo+(Ngeo+1)
CornerNodeIDswitch(7)=(Ngeo+1)**2*Ngeo+(Ngeo+1)**2
CornerNodeIDswitch(8)=(Ngeo+1)**2*Ngeo+(Ngeo+1)*Ngeo+1

!assign nodes and get physical coordinates to Node pointers (new procedure compared to old mapping due to new meshformat)
DO iElem=FirstElemInd,LastElemInd
  aElem=>Elems(iElem)%ep
  !iNode=ElemInfo(ELEM_FirstNodeInd,iElem) !first index -1 in NodeInfo
  DO jNode=1,8
    iNode = ElemInfo(ELEM_FirstNodeInd,iElem)+CornerNodeIDswitch(jNode)
    NodeID=ABS(NodeInfo(iNode))       !global, unique NodeID
    iNodeP=INVMAP(NodeID,nNodes,NodeMap)  ! index in local Nodes pointer array
    IF(iNodeP.LE.0) STOP 'Problem in INVMAP'
    IF(.NOT.ASSOCIATED(Nodes(iNodeP)%np))THEN
      ALLOCATE(Nodes(iNodeP)%np)
      Nodes(iNodeP)%np%ind = NodeID
      Nodes(iNodeP)%np%x   = NodeCoords_indx(:,iNode-offsetNodeID)
    END IF
    aElem%Node(jNode)%np=>Nodes(iNodeP)%np
  END DO
  CALL createSides(aElem)
END DO
DEALLOCATE(NodeCoords_indx)


! get physical coordinates
IF(useCurveds)THEN
  ALLOCATE(NodeCoords(3,0:NGeo,0:NGeo,0:NGeo,nElems))
  CALL ReadArray('NodeCoords',2,(/3_IK,INT(nElems*(NGeo+1)**3,IK)/),INT(offsetElem*(NGeo+1)**3,IK),2,RealArray=NodeCoords)
ELSE
  ALLOCATE(NodeCoords(   3,0:1,   0:1,   0:1,   nElems))
  ALLOCATE(NodeCoordsTmp(3,0:NGeo,0:NGeo,0:NGeo,nElems))
  CALL ReadArray('NodeCoords',2,(/3_IK,INT(nElems*(NGeo+1)**3,IK)/),INT(offsetElem*(NGeo+1)**3,IK),2,RealArray=NodeCoordsTmp)
  NodeCoords(:,0,0,0,:)=NodeCoordsTmp(:,0,   0,   0,   :)
  NodeCoords(:,1,0,0,:)=NodeCoordsTmp(:,NGeo,0,   0,   :)
  NodeCoords(:,0,1,0,:)=NodeCoordsTmp(:,0,   NGeo,0,   :)
  NodeCoords(:,1,1,0,:)=NodeCoordsTmp(:,NGeo,NGeo,0,   :)
  NodeCoords(:,0,0,1,:)=NodeCoordsTmp(:,0,   0,   NGeo,:)
  NodeCoords(:,1,0,1,:)=NodeCoordsTmp(:,NGeo,0,   NGeo,:)
  NodeCoords(:,0,1,1,:)=NodeCoordsTmp(:,0,   NGeo,NGeo,:)
  NodeCoords(:,1,1,1,:)=NodeCoordsTmp(:,NGeo,NGeo,NGeo,:)
  DEALLOCATE(NodeCoordsTmp)
ENDIF
IF(.NOT.useCurveds) NGeo=1

!! IJK SORTING --------------------------------------------
!!read local ElemInfo from data file
!CALL DatasetExists(File_ID,'nElems_IJK',DExist)
!IF(DExist)THEN
!  CALL ReadArray('nElems_IJK',1,(/3/),0,1,IntegerArray=nElems_IJK)
!  ALLOCATE(Elem_IJK(3,nLocalElems))
!  CALL ReadArray('Elem_IJK',2,(/3,nElems/),offsetElem,2,IntegerArray=Elem_IJK)
!END IF

! Get Mortar specific arrays
isMortarMeshExists=.FALSE.
iMortar=0
CALL DatasetExists(File_ID,'isMortarMesh',isMortarMeshExists,.TRUE.)
IF(isMortarMeshExists)&
    CALL ReadAttribute(File_ID,'isMortarMesh',1,IntegerScalar=iMortar)
isMortarMesh=(iMortar.EQ.1)
IF(isMortarMesh)THEN
  CALL ReadAttribute(File_ID,'NgeoTree',1,IntegerScalar=NGeoTree)
  CALL ReadAttribute(File_ID,'nTrees',1,IntegerScalar=nGlobalTrees)

  ALLOCATE(xiMinMax(3,2,1:nElems))
  ! Associate construct for integer KIND=8 possibility
  ASSOCIATE (&
        nElems     => INT(nElems,IK)     ,&
        offsetElem => INT(offsetElem,IK) )
    xiMinMax=-1.
    CALL ReadArray('xiMinMax',3,(/3_IK,2_IK,nElems/),offsetElem,3,RealArray=xiMinMax)

    ALLOCATE(ElemToTree(1:nElems))
    ElemToTree=0
    CALL ReadArray('ElemToTree',1,(/nElems/),offsetElem,1,IntegerArray_i4=ElemToTree)
  END ASSOCIATE

  ! only read trees, connected to a procs elements
  offsetTree=MINVAL(ElemToTree)-1
  ElemToTree=ElemToTree-offsetTree
  nTrees=MAXVAL(ElemToTree)

  ALLOCATE(TreeCoords(3,0:NGeoTree,0:NGeoTree,0:NGeoTree,nTrees))
  TreeCoords=-1.
  ! Associate construct for integer KIND=8 possibility
  ASSOCIATE (&
        NGeoTree   => INT(NGeoTree)            ,&
        nTrees     => INT(nTrees)              ,&
        offsetTree => INT(offsetTree)          )
    CALL ReadArray('TreeCoords',2,(/3_IK,(NGeoTree+1_IK)**3_IK*nTrees/),&
        (NGeoTree+1_IK)**3_IK*offsetTree,2,RealArray=TreeCoords)
  END ASSOCIATE
ELSE
  nTrees=0
END IF

DEALLOCATE(ElemInfo,SideInfo,NodeInfo,NodeMap)

CALL CloseDataFile()

!----------------------------------------------------------------------------------------------------------------------------
!                              COUNT SIDES
!----------------------------------------------------------------------------------------------------------------------------
! Readin is now finished
nBCSides=0
nAnalyzeSides=0
nMortarSides=0
nSides=0
nPeriodicSides=0
nMPIPeriodics=0
nMPISides=0
#if USE_MPI
ALLOCATE(MPISideCount(0:nProcessors-1))
MPISideCount=0
#endif
DO iElem=FirstElemInd,LastElemInd
  aElem=>Elems(iElem)%ep
  DO iLocSide=1,6
    aSide=>aElem%Side(iLocSide)%sp
    ! LOOP over mortars, if no mortar, then LOOP is executed once
    nMortars=aSide%nMortars
    DO iMortar=0,nMortars
      IF(iMortar.GT.0) aSide=>aElem%Side(iLocSide)%sp%mortarSide(iMortar)%sp
      aSide%tmp=0
    END DO !iMortar
  END DO !iLocSide
END DO !iElem
DO iElem=FirstElemInd,LastElemInd
  aElem=>Elems(iElem)%ep
  DO iLocSide=1,6
    aSide=>aElem%Side(iLocSide)%sp
    nMortars=aSide%nMortars
    DO iMortar=0,nMortars
      IF(iMortar.GT.0) aSide=>aElem%Side(iLocSide)%sp%mortarSide(iMortar)%sp

      IF(aSide%tmp.EQ.0)THEN
        nSides=nSides+1
        aSide%tmp=-1 !used as marker
        IF(ASSOCIATED(aSide%connection)) aSide%connection%tmp=-1
        IF(aSide%BCindex.NE.0)THEN !side is BC or periodic side
          nAnalyzeSides=nAnalyzeSides+1
          IF(ASSOCIATED(aSide%connection))THEN
            IF(BoundaryType(aSide%BCindex,BC_TYPE).EQ.1)THEN
              nPeriodicSides=nPeriodicSides+1
#if USE_MPI
              IF(aSide%NbProc.NE.-1) nMPIPeriodics=nMPIPeriodics+1
#endif
            END IF
          ELSE
            IF(aSide%MortarType.EQ.0)THEN !really a BC side
              nBCSides=nBCSides+1
            END IF
          END IF
        END IF
        IF(aSide%MortarType.GT.0) nMortarSides=nMortarSides+1
#if USE_MPI
        IF(aSide%NbProc.NE.-1) THEN
          nMPISides=nMPISides+1
          MPISideCount(aSide%NbProc)=MPISideCount(aSide%NbProc)+1
        END IF
#endif
      END IF
    END DO !iMortar
  END DO !iLocSide
END DO !iElem
nInnerSides=nSides-nBCSides-nMPISides-nMortarSides !periodic side count to inner side!!!

LOGWRITE(*,*)'-------------------------------------------------------'
LOGWRITE(*,'(A22,I8)')'nSides:',nSides
LOGWRITE(*,'(A22,I8)')'nBCSides:',nBCSides
LOGWRITE(*,'(A22,I8)')'nMortarSides:',nMortarSides
LOGWRITE(*,'(A22,I8)')'nInnerSides:',nInnerSides
LOGWRITE(*,'(A22,I8)')'nMPISides:',nMPISides
LOGWRITE(*,*)'-------------------------------------------------------'
 !now MPI sides
#if USE_MPI
nNBProcs=0
DO iProc=0,nProcessors-1
  IF(iProc.EQ.myRank) CYCLE
  IF(MPISideCount(iProc).GT.0) nNBProcs=nNbProcs+1
END DO
IF(nNbProcs.EQ.0)THEN !MPI + 1Proc case !
  ALLOCATE(NbProc(1),nMPISides_Proc(1))
  nNbProcs=1
  NbProc=0
  nMPISides_Proc=0
ELSE
  ALLOCATE(NbProc(nNbProcs),nMPISides_Proc(1:nNbProcs))
  iNbProc=0
  DO iProc=0,nProcessors-1
    IF(iProc.EQ.myRank) CYCLE
    IF(MPISideCount(iProc).GT.0) THEN
      iNbProc=iNbProc+1
      NbProc(iNbProc)=iProc
      ! compute number of MPISides per neighbor proc and divide by two
      nMPISides_Proc(iNBProc)=MPISideCount(iProc)
    END IF
  END DO
END IF
DEALLOCATE(MPISideCount)
#endif /*USE_MPI*/

ReduceData(1)=nElems
ReduceData(2)=nSides
ReduceData(3)=nNodes
ReduceData(11)=nNodeIDs
ReduceData(4)=nInnerSides
ReduceData(5)=nPeriodicSides
ReduceData(6)=nBCSides
ReduceData(7)=nMPISides
ReduceData(8)=nAnalyzeSides
ReduceData(9)=nMortarSides
ReduceData(10)=nMPIPeriodics

#if USE_MPI
CALL MPI_ALLREDUCE(MPI_IN_PLACE,ReduceData,11,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,iError)
#endif /*USE_MPI*/

nGlobalMortarSides=ReduceData(9)

IF(MPIRoot)THEN
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nElems | ',ReduceData(1) !nElems
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nNodes, unique | ',ReduceData(3) !nNodes
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nNodes, total  | ',ReduceData(11) !nNodes
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nSides         | ',ReduceData(2)-ReduceData(7)/2
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nSides,    BC  | ',ReduceData(6) !nBCSides
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nSides,   MPI  | ',ReduceData(7)/2 !nMPISides
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nSides, Inner  | ',ReduceData(4) !nInnerSides
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nSides,Mortar  | ',nGlobalMortarSides
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nPeriodicSides,Total | ',ReduceData(5)-ReduceData(10)/2
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nPeriodicSides,Inner | ',ReduceData(5)-ReduceData(10)
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nPeriodicSides,  MPI | ',ReduceData(10)/2 !nPeriodicSides
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','nAnalyzeSides | ',ReduceData(8) !nAnalyzeSides
  WRITE(UNIT_stdOut,'(A,A34,L1)')' |','useCurveds | ',useCurveds
  WRITE(UNIT_stdOut,'(A,A34,I0)')' |','Ngeo | ',Ngeo
  WRITE(UNIT_stdOut,'(132("."))')
END IF

LOGWRITE_BARRIER
SWRITE(UNIT_stdOut,'(132("."))')
END SUBROUTINE ReadMesh


SUBROUTINE GetNodeMap()
!===================================================================================================================================
! take NodeInfo array, sort it, eliminate mulitple IDs and return the Mapping 1->NodeID1, 2->NodeID2, ...
! this is useful if the NodeID list of the mesh are not contiguous, essentially occuring when using domain decomposition (MPI)
!===================================================================================================================================
! MODULES
USE MOD_mesh_vars,ONLY:nNodes
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                            :: temp(nNodeIDs+1),i,nullpos
!===================================================================================================================================
temp(1)=0
temp(2:nNodeIDs+1)=NodeInfo
!sort
CALL Qsort1Int(temp)
nullpos=INVMAP(0,nNodeIDs+1,temp)
!count unique entries
nNodes=1
DO i=nullpos+2,nNodeIDs+1
  IF(temp(i).NE.temp(i-1)) nNodes = nNodes+1
END DO
!associate unique entries
ALLOCATE(NodeMap(nNodes))
nNodes=1
NodeMap(1)=temp(nullpos+1)
DO i=nullpos+2,nNodeIDs+1
  IF(temp(i).NE.temp(i-1)) THEN
    nNodes = nNodes+1
    NodeMap(nNodes)=temp(i)
  END IF
END DO
END SUBROUTINE GetNodeMap


FUNCTION INVMAP(ID,nIDs,ArrID)
!===================================================================================================================================
! find the inverse Mapping p.e. NodeID-> entry in NodeMap (a sorted array of unique NodeIDs), using bisection
! if Index is not in the range, -1 will be returned, if it is in the range, but is not found, 0 will be returned!!
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)                :: ID            ! ID to search for
INTEGER, INTENT(IN)                :: nIDs          ! size of ArrID
INTEGER, INTENT(IN)                :: ArrID(nIDs)   ! 1D array of IDs
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER                            :: INVMAP               ! index of ID in NodeMap array
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                            :: i,maxSteps,low,up,mid
!===================================================================================================================================
INVMAP=0
maxSteps=INT(LOG(REAL(nIDs))*1.4426950408889634556)+1    !1/LOG(2.)=1.4426950408889634556
low=1
up=nIDs
IF((ID.LT.ArrID(low)).OR.(ID.GT.ArrID(up))) THEN
  !WRITE(*,*)'WARNING, Node Index Not in local range -> set to -1'
  INVMAP=-1  ! not in the range!
  RETURN
END IF
IF(ID.EQ.ArrID(low))THEN
  INVMAP=low
ELSEIF(ID.EQ.ArrID(up))THEN
  INVMAP=up
ELSE
  !bisection
  DO i=1,maxSteps
    mid=(up-low)/2+low
    IF(ID .EQ. ArrID(mid))THEN
      INVMAP=mid                     !index found!
      EXIT
    ELSEIF(ID .GT. ArrID(mid))THEN ! seek in upper half
      low=mid
    ELSE
      up=mid
    END IF
  END DO
END IF
END FUNCTION INVMAP


#if USE_MPI
FUNCTION ELEMIPROC(ElemID)
!===================================================================================================================================
!> Find the id of a processor on which an element with a given ElemID lies, based on the MPI element offsets defined earlier.
!> Use a bisection algorithm for faster search.
!===================================================================================================================================
! MODULES
USE MOD_Globals,   ONLY:nProcessors
USE MOD_MPI_vars,  ONLY:offsetElemMPI
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)                :: ElemID     !< (IN)  NodeID to search for
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER                            :: ELEMIPROC  !< (OUT) processor id
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                            :: i,maxSteps,low,up,mid
!===================================================================================================================================
ELEMIPROC=0
maxSteps=INT(LOG(REAL(nProcessors))*1.4426950408889634556)+1    !1/LOG(2.)=1.4426950408889634556
low=0
up=nProcessors-1
IF((ElemID.GT.offsetElemMPI(low)).AND.(ElemID.LE.offsetElemMPI(low+1)))THEN
  ELEMIPROC=low
ELSEIF((ElemID.GT.offsetElemMPI(up)).AND.(ElemID.LE.offsetElemMPI(up+1)))THEN
  ELEMIPROC=up
ELSE
  !bisection
  DO i=1,maxSteps
    mid=(up-low)/2+low
    IF((ElemID.GT.offsetElemMPI(mid)).AND.(ElemID.LE.offsetElemMPI(mid+1)))THEN
      ELEMIPROC=mid                     !index found!
      EXIT
    ELSEIF(ElemID .GT. offsetElemMPI(mid+1))THEN ! seek in upper half
      low=mid+1
    ELSE
      up=mid
    END IF
  END DO
END IF
END FUNCTION ELEMIPROC
#endif /*USE_MPI*/

RECURSIVE SUBROUTINE Qsort1Int(A)
!===================================================================================================================================
! QuickSort for integer array A
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(INOUT)            :: A(:)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: marker
!===================================================================================================================================
IF(SIZE(A).GT.1) THEN
  CALL Partition1Int(A,marker)
  CALL Qsort1Int(A(:marker-1))
  CALL Qsort1Int(A(marker:))
END IF
RETURN
END SUBROUTINE Qsort1Int



SUBROUTINE Partition1Int(A,marker)
!===================================================================================================================================
! Neeeded by QuickSort
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(INOUT)            :: A(:)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER,INTENT(OUT)              :: marker
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: i,j
INTEGER                          :: temp,x
!===================================================================================================================================
x= A(1)
i= 0
j= SIZE(A)+1
DO
  j=j-1
  DO
    IF(A(j).LE.x) EXIT
    j=j-1
  END DO
  i=i+1
  DO
    IF(A(i).GE.x) EXIT
    i=i+1
  END DO
  IF(i.LT.j)THEN
    ! exchange A(i) and A(j)
    temp=A(i)
    A(i)=A(j)
    A(j)=temp
  ELSEIF(i.EQ.j)THEN
    marker=i+1
    RETURN
  ELSE
    marker=i
    RETURN
  ENDIF
END DO
RETURN
END SUBROUTINE Partition1Int

END MODULE MOD_Mesh_ReadIn

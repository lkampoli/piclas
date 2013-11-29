MODULE MOD_Riemann
!===================================================================================================================================
! Contains routines to compute the riemann (Advection, Diffusion) for a given Face
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
INTERFACE Riemann
  MODULE PROCEDURE Riemann
END INTERFACE

PUBLIC::Riemann
!===================================================================================================================================

CONTAINS

SUBROUTINE Riemann(F,U_L,U_R,nv,t1,t2)
!===================================================================================================================================
! Computes the numerical flux
! Conservative States are rotated into normal direction in this routine and are NOT backrotatet: don't use it after this routine!!
!===================================================================================================================================
! MODULES
USE MOD_PreProc ! PP_N
USE MOD_Equation_Vars,ONLY:eta_c,c,c2,c_corr,c_corr_c,c_corr_c2
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,DIMENSION(PP_nVar,0:PP_N,0:PP_N),INTENT(IN) :: U_L,U_R
REAL,INTENT(IN)                                  :: nv(3,0:PP_N,0:PP_N),t1(3,0:PP_N,0:PP_N),t2(3,0:PP_N,0:PP_N)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                                 :: F(PP_nVar,0:PP_N,0:PP_N)
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
REAL                                             :: n_loc(3),A_p(4,4),A_n(4,4)
INTEGER                                          :: Count_1,Count_2
!REAL                                             :: D(3,3)                  ! auxiliary matrices used 
!REAL                                             :: E(3,3), E_trans(3,3)    ! auxiliary matrices used
!===================================================================================================================================
! Gauss point i,j
DO Count_2=0,PP_N
  DO Count_1=0,PP_N
    n_loc(:)=nv(:,Count_1,Count_2)


!--- for original version see below (easier to understand)
  
    A_p(1,1) = n_loc(1)*n_loc(1)*c_corr_c
    A_p(1,2) = n_loc(1)*n_loc(2)*c_corr_c
    A_p(1,3) = n_loc(1)*n_loc(3)*c_corr_c
    A_p(2,1) = A_p(1,2)                  
    A_p(2,2) = n_loc(2)*n_loc(2)*c_corr_c
    A_p(2,3) = n_loc(2)*n_loc(3)*c_corr_c
    A_p(3,1) = A_p(1,3)                    
    A_p(3,2) = A_p(2,3)                    
    A_p(3,3) = n_loc(3)*n_loc(3)*c_corr_c

    !negative A-Matrix
    A_n(1:3,1:3)=-A_p(1:3,1:3)
  
   ! !positive A-Matrix-Divergence-Correction-Term
    A_p(1,4) = c_corr_c2*n_loc(1)
    A_p(2,4) = c_corr_c2*n_loc(2)
    A_p(3,4) = c_corr_c2*n_loc(3)   
    A_p(4,1) = c_corr*n_loc(1)
    A_p(4,2) = c_corr*n_loc(2)
    A_p(4,3) = c_corr*n_loc(3)
    A_p(4,4) = c_corr_c
    !negative A-Matrix-Divergence-Correction-Term
    A_n(1:3,4) = A_p(1:3,4) !c_corr*c*c*n(1)           
    A_n(4,1:3)= A_p(4,1:3)
    A_n(4,4)  =-A_p(4,4)
    ! Warum 0.5 -> Antwort im Taube/Dumbser-Paper. Im Munz/Schneider Paper fehlt das 0.5 lustigerweise.

!--- Original Version:

!    A_p=0.
!    A_n=0.
!  
!    !D-Teilmatrix: Since chi and gamma is equal we
!    ! consider D(chi,gamma) = D(gamma,chi)
!    ! ATTENTION: if chi .ne. gamma this have to be changed. 
!    ! Then we need D_1 and D_2
!    D(1,1) = c + n_loc(1)*n_loc(1)*eta_c   !  D(1,1)=(1.+n_loc(1)*n_loc(1)*(eta-1.))*c
!    D(1,2) = n_loc(1)*n_loc(2)*eta_c            !  D(1,2)=n_loc(1)*n_loc(2)*(eta-1)*c
!    D(1,3) = n_loc(1)*n_loc(3)*eta_c            !  D(1,3)=n_loc(1)*n_loc(3)*(eta-1)*c
!    D(2,1) = D(1,2)                          !  D(2,1)=n_loc(1)*n_loc(2)*(eta-1)*c
!    D(2,2) = c + n_loc(2)*n_loc(2)*eta_c   !  D(2,2)=(1.+n_loc(2)*n_loc(2)*(eta-1.))*c
!    D(2,3) = n_loc(2)*n_loc(3)*eta_c            !  D(2,3)=n_loc(2)*n_loc(3)*(eta-1)*c
!    D(3,1) = D(1,3)                          !  D(3,1)=n_loc(1)*n_loc(3)*(eta-1)*c
!    D(3,2) = D(2,3)                          !  D(3,2)=n_loc(2)*n_loc(3)*(eta-1)*c     
!    D(3,3) = c+n_loc(3)*n_loc(3)*eta_c     !  D(3,3)=(1.+n_loc(3)*n_loc(3)*(mu-1.))*c
!    ! epsilon-Teilmatrix
!    !E_trans=transpose(E)
!    E(1,:)= (/0.,n_loc(3),-n_loc(2)/)
!    E(2,:)= (/-n_loc(3),0.,n_loc(1)/)
!    E(3,:)= (/n_loc(2),-n_loc(1),0./)
!    E_trans(1,:)= (/0.,-n_loc(3),n_loc(2)/)
!    E_trans(2,:)= (/n_loc(3),0.,-n_loc(1)/)
!    E_trans(3,:)= (/-n_loc(2),n_loc(1),0./)
!    !composition of the Matrix
!    !positive A-Matrx
!    A_p(1:3,1:3)=D(:,:)
!    A_p(1:3,4:6)=c2*E(:,:) ! c*c*E(:,:)
!    A_p(4:6,1:3)=E_trans(:,:)
!    A_p(4:6,4:6)=D(:,:)
!    !negative A-Matrix
!    A_n(1:3,1:3)=-D(:,:)
!    A_n(1:3,4:6)= A_p(1:3,4:6)   ! c*c*E(:,:)
!    A_n(4:6,1:3)= E_trans(:,:)
!    A_n(4:6,4:6)=-D(:,:)
!  
!   ! !positive A-Matrix-Divergence-Correction-Term
!    A_p(1,8) = c_corr_c2*n_loc(1)
!    A_p(2,8) = c_corr_c2*n_loc(2)
!    A_p(3,8) = c_corr_c2*n_loc(3)
!    A_p(4,7) = c_corr*n_loc(1)
!    A_p(5,7) = c_corr*n_loc(2)
!    A_p(6,7) = c_corr*n_loc(3)
!    A_p(7,4) = c_corr_c2*n_loc(1)
!    A_p(7,5) = c_corr_c2*n_loc(2)
!    A_p(7,6) = c_corr_c2*n_loc(3)
!    A_p(7,7) = c_corr_c
!    A_p(8,1) = c_corr*n_loc(1)
!    A_p(8,2) = c_corr*n_loc(2)
!    A_p(8,3) = c_corr*n_loc(3)
!    A_p(8,8) = c_corr_c
!    !negative A-Matrix-Divergence-Correction-Term
!    A_n(1,8) = A_p(1,8) !c_corr*c*c*n(1)
!    A_n(2,8) = A_p(2,8) !c_corr*c*c*n(2)
!    A_n(3,8) = A_p(3,8) !c_corr*c*c*n(3)
!    A_n(4,7) = A_p(4,7) !c_corr*n(1)
!    A_n(5,7) = A_p(5,7) !c_corr*n(2)
!    A_n(6,7) = A_p(6,7) !c_corr*n(3)
!    !A_n(7,:)=(/0.,0.,0.,c_corr*c*c*n(1),c_corr*c*c*n(2),c_corr*c*c*n(3),-c_corr*c,0./)
!    A_n(7,1:6)=  A_p(7,1:6)
!    A_n(7,7)  = -A_p(7,7)
!    !A_n(8,:)=(/c_corr*n(1),c_corr*n(2),c_corr*n(3),0.,0.,0.,0.,-c_corr*c/)
!    A_n(8,1:7)= A_p(8,1:7)
!    A_n(8,8)  =-A_p(8,8)
!    ! Warum 0.5 -> Antwort im Taube/Dumbser-Paper. Im Munz/Schneider Paper fehlt das 0.5 lustigerweise.
    
    F(:,Count_1,Count_2)=0.5*(MATMUL(A_n,U_R(:,Count_1,Count_2))+MATMUL(A_p,U_L(:,Count_1,Count_2)))
  END DO
END DO
END SUBROUTINE Riemann


END MODULE MOD_Riemann
module geant4

  use floatPrecision
  use crcoall
  use iso_c_binding, only: C_NULL_CHAR
  use numerical_constants

  implicit none

  real(kind=fPrec) :: g4_ecut
  real(kind=fPrec) :: g4_rcut
  real(kind=fPrec) :: g4_absecut
  integer :: g4_physics

  character(len=64) :: phys_str

  logical geant4_flag

contains

subroutine geant4_fortran_init()

  implicit none

!Set default values

!Default physics = FTFP_BERT
  g4_physics = 0

!Default ecut = none
  g4_ecut = zero

!Default rcut = none
  g4_rcut = zero

!Default absecut = none
  g4_absecut = zero

end subroutine

subroutine geant4_daten(inLine,iErr)

  use string_tools

  implicit none

  character(len=*), intent(in)    :: inLine
  logical,          intent(inout) :: iErr

  character(len=:), allocatable :: lnSplit(:)
  integer nSplit
  logical spErr, cErr

  call chr_split(inLine,lnSplit,nSplit,spErr)
  if(spErr) then
    write(lout,"(a)") "GEANT4> ERROR Failed to parse input line."
    iErr = .true.
    return
  end if

  if(nSplit /= 2) then
    write(lout,"(a,i0)") "GEANT4> ERROR Expected 2 entries per line, got ",nSplit
    iErr = .true.
    return
  end if

!  For input debugging if needed
!  write(lout,*) '1: ', getfields_fields(1)(1:getfields_lfields(1))
!  write(lout,*) '2: ', getfields_fields(2)(1:getfields_lfields(2))

!relative energy cut
  if(lnSplit(1) == 'RELENERGYCUT') then
    call chr_cast(lnSplit(2),g4_ecut,cErr)

!relative rigidity cut
  else if(lnSplit(1) == 'RELRIGIDITYCUT') then
    call chr_cast(lnSplit(2),g4_rcut,cErr)

!PREFIX sixtrack_
  else if(lnSplit(1) == 'ABSENERGYCUT') then
    call chr_cast(lnSplit(2),g4_absecut,cErr)

  else if(lnSplit(1) == 'RANGECUT') then
    call chr_cast(lnSplit(2),g4_absecut,cErr)

!Physics to use number
!FTFP_BERT
!QGSP_BERT
!Anything else? -> error
  else if(lnSplit(1) == 'PHYSICS') then
    phys_str = trim(lnSplit(2)) // C_NULL_CHAR
    if(phys_str .eq. 'FTFP_BERT') then
      g4_physics = 0
    else if(phys_str .eq. 'QGSP_BERT') then
      g4_physics = 1
    else
      write(lout,'(a)') 'GEANT4> WARNING: Unknown physics model requested: ',phys_str, ' defaulting to FTFP_BERT'
      g4_physics = 0
    end if
  else if(lnSplit(1) == 'RETURN') then
    write(lout,'(a)') 'GEANT4> WARNING: RETURN not yet implemented!'
  end if

!Check configuration

!check + enable flags
end subroutine

subroutine geant4_parseInputDone

  implicit none

  !GEANT4 is enabled
  geant4_flag = .true.
end subroutine

end module geant4


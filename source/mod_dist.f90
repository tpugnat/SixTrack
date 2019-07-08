! ================================================================================================ !
!  A. Mereghetti and D. Sinuela Pastor, for the FLUKA Team
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Last modified: 2018-10-30
!  Read a beam distribution
!
!  Format of the input file:
!    id:         unique identifier of the particle (integer)
!    gen:        parent ID (integer)
!    weight:     statistical weight of the particle (double: >0.0)
!    x,  y,  s:  particle position  [m]
!    xp, yp, zp: particle direction (tangents) []
!    aa, zz:     mass and atomic number
!    m:          rest mass [GeV/c2]
!    pc:         particle momentum [GeV/c]
!    dt:         time delay with respect to the reference particle [s]
!
!    aa,zz and m are now taken into account for hisix!
!
!  NOTA BENE:
!  - id, gen and weight are assigned by the fluka_mod_init subroutine;
!  - z and zp are actually useless (but we never know);
!  - in case the file contains less particle than napx, napx is re-assigned
!
! ================================================================================================ !
module mod_dist

  use crcoall
  use floatPrecision
  use parpro, only : mFileName

  implicit none

  logical,                  public,  save :: dist_enable    = .false. ! DIST input block given
  logical,                  private  save :: dist_echo      = .false. ! Echo the read distribution?
  logical,                  private, save :: dist_hasFormat = .false. ! Whether the FORMAT keyword exists in block or not
  logical,                  private, save :: dist_libRead   = .false. ! Read file with dist library instead of internal reader
  character(len=mFileName), private, save :: dist_distFile  = " "     ! File name for reading the distribution
  character(len=mFileName), private, save :: dist_echoFile  = " "     ! File name for echoing the distribution

  integer,          allocatable, private, save :: dist_colFormat(:) ! The format of the file columns
  real(kind=fPrec), allocatable, private, save :: dist_colScale(:)  ! Scaling factor for the file columns
  integer,                       private, save :: dist_nColumns = 0 ! The number of columns in the file

  character(len=:), allocatable, private, save :: dist_partLine(:)  ! PARTICLE definitions in the block
  integer,                       private, save :: dist_numPart = 0  ! Number of PARTICLE keywords in block

  !  Column formats
  ! ================
  integer, parameter :: dist_fmtNONE        = 0  ! Column ignored
  integer, parameter :: dist_fmtPartID      = 1  ! Paricle ID
  integer, parameter :: dist_fmtParentID    = 2  ! Particle parent ID (for secondary particles, otherwise equal particle ID)

  ! Physical Coordinates
  integer, parameter :: dist_fmtX           = 11 ! Horizontal position
  integer, parameter :: dist_fmtY           = 12 ! Vertical positiom
  integer, parameter :: dist_fmtXP          = 13 ! Horizontal angle
  integer, parameter :: dist_fmtYP          = 14 ! Vertical angle
  integer, parameter :: dist_fmtPX          = 15 ! Horizontal momentum
  integer, parameter :: dist_fmtPY          = 16 ! Vertical momentum
  integer, parameter :: dist_fmtSIGMA       = 17 ! Longitudinal relative position
  integer, parameter :: dist_fmtDT          = 18 ! Time delay
  integer, parameter :: dist_fmtE           = 19 ! Particle energy
  integer, parameter :: dist_fmtP           = 20 ! Particle momentum
  integer, parameter :: dist_fmtDEE0        = 21 ! Relative particle energy (to reference particle)
  integer, parameter :: dist_fmtDPP0        = 22 ! Relative particle momentum (to reference particle)

  ! Normalised Coordinates
  integer, parameter :: dist_fmtX_NORM      = 31 ! Normalised horizontal position
  integer, parameter :: dist_fmtY_NORM      = 32 ! Normalised vertical positiom
  integer, parameter :: dist_fmtXP_NORM     = 33 ! Normalised horizontal angle
  integer, parameter :: dist_fmtYP_NORM     = 34 ! Normalised vertical angle
  integer, parameter :: dist_fmtPX_NORM     = 35 ! Normalised horizontal momentum
  integer, parameter :: dist_fmtPY_NORM     = 36 ! Normalised vertical momentum
  integer, parameter :: dist_fmtSIGMA_NORM  = 37 ! Normalised longitudinal relative position
  integer, parameter :: dist_fmtDT_NORM     = 38 ! Normalised time delay
  integer, parameter :: dist_fmtE_NORM      = 39 ! Normalised particle energy
  integer, parameter :: dist_fmtP_NORM      = 40 ! Normalised particle momentum
  integer, parameter :: dist_fmtDEE0_NORM   = 41 ! Normalised relative particle energy (to reference particle)
  integer, parameter :: dist_fmtDPP0_NORM   = 42 ! Normalised relative particle momentum (to reference particle)

  ! Ion Columns
  integer, parameter :: dist_fmtMASS        = 51 ! Particle mass
  integer, parameter :: dist_fmtCHARGE      = 52 ! Particle Charge
  integer, parameter :: dist_fmtIonA        = 53 ! Ion atomic mass
  integer, parameter :: dist_fmtIonZ        = 54 ! Ion atomic number
  integer, parameter :: dist_fmtPDGID       = 55 ! Particle PDG ID

contains

! ================================================================================================ !
!  Master Module Subrotuine
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Created: 2019-07-08
!  Updated: 2019-07-08
!  Called from main_cr if dist_enable is true. This should handle everything needed.
! ================================================================================================ !
subroutine dist_generateDist

  use mod_particles

  logical hasParticles

  hasParticles = .false.

  if(dist_numPart > 0) then
    call dist_parseParticles
    hasParticles = .true.
  end if

  if(dist_distFile /= " ") then
    call dist_readDist
    hasParticles = .true.
  end if

  if(hasParticles) then
    call dist_finaliseDist
    call part_applyClosedOrbit
    if(dist_echo) then
      call dist_echoDist
    end if
  end if

end subroutine dist_generateDist

! ================================================================================================ !
!  A. Mereghetti and D. Sinuela Pastor, for the FLUKA Team
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Updated: 2018-10-30
! ================================================================================================ !
subroutine dist_parseInputLine(inLine, iLine, iErr)

  use parpro
  use mod_alloc
  use mod_units
  use string_tools

  character(len=*), intent(in)    :: inLine
  integer,          intent(inout) :: iLine
  logical,          intent(inout) :: iErr

  character(len=:), allocatable   :: lnSplit(:)
  integer nSplit, i
  logical spErr, cErr

  call chr_split(inLine, lnSplit, nSplit, spErr)
  if(spErr) then
    write(lerr,"(a)") "DIST> ERROR Failed to parse input line."
    iErr = .true.
    return
  end if
  if(nSplit == 0) return

  select case(lnSplit(1))

  case("FORMAT")
    if(nSplit < 2) then
      write(lerr,"(a,i0)") "DIST> ERROR FORMAT takes at least 1 argument, got ",nSplit-1
      write(lerr,"(a)")    "DIST>       FORMAT [list of columns]"
      iErr = .true.
      return
    end if
    do i=2,nSplit
      call dist_setColumnFormat(lnSplit(i),cErr)
      if(cErr) then
        iErr = .true.
        return
      end if
    end do
    dist_hasFormat = .true.

  case("READ")
    if(nSplit /= 2 .or. nSplit /= 3) then
      write(lerr,"(a,i0)") "DIST> ERROR READ takes 1 or 2 arguments, got ",nSplit-1
      write(lerr,"(a)")    "DIST>       READ filename [LIBDIST]"
      iErr = .true.
      return
    end if
    dist_distFile = trim(lnSplit(2))
    if(nSplit > 2) call chr_cast(lnSplit(3), dist_libRead, cErr)
    if(cErr) then
      iErr = .true.
      return
    end if

  case("PARTICLE")
    if(dist_hasFormat .eqv. .false.) then
      write(lerr,"(a,i0)") "DIST> ERROR PARTICLE requires a FORMAT definition to be defined first"
      iErr = .true.
      return
    end if
    if(nSplit /= dist_nColumns + 1) then
      write(lerr,"(a)")       "DIST> ERROR PARTICLE values must match the number of definitions in FORMAT"
      write(lerr,"(2(a,i0))") "DIST>       Got ",nsplit-1," values, but FORMAT defines ",dist_nColumns
      iErr = .true.
      return
    end if
    dist_numPart = dist_numPart + 1
    call alloc(dist_partLine, mInputLn, dist_numPart, " ", "dist_partLine")
    dist_partLine(dist_numPart) = trim(inLine)

  case("ECHO")
    if(nSplit >= 2) then
      dist_echoFile = trim(lnSplit(2))
    else
      dist_echoFile = "echo_distribution.dat"
    end if
    dist_echo = .true.

  case default
    write(lerr,"(a)") "DIST> ERROR Unknown keyword '"//trim(lnSplit(1))//"'."
    iErr = .true.
    return

  end select

end subroutine dist_parseInputLine

! ================================================================================================ !
!  Parse File Column Formats
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Created: 2019-07-05
!  Updated: 2019-07-08
! ================================================================================================ !
subroutine dist_setColumnFormat(fmtName, fErr)

  use crcoall
  use string_tools
  use numerical_constants

  character(len=*), intent(in)  :: fmtName
  logical,          intent(out) :: fErr

  character(len=20) fmtBase
  character(len=10) fmtUnit
  real(kind=fPrec)  uFac
  integer           c, unitPos, fmtLen

  fErr = .false.

  fmtLen = len_trim(fmtName)
  if(fmtLen < 1) then
    write(lerr,"(a)") "DIST> ERROR Unknown column format '"//trim(fmtName)//"'"
    fErr = .true.
  end if

  unitPos = -1
  do c=1,fmtLen
    if(fmtName(c:c) == "[") then
      unitPos = c
      exit
    end if
  end do

  if(unitPos > 1 .and. fmtLen > unitPos+1) then
    fmtBase = trim(fmtName(1:unitPos-1))
    fmtUnit = trim(fmtName(unitPos:fmtLen))
  else
    fmtBase = trim(fmtName)
    fmtUnit = "[none]"
  end if

  select case(chr_toUpper(fmtBase))

  case("OFF","SKIP") ! Ignored
    call dist_appendFormat(dist_fmtNONE, one)
  case("ID") ! Particle ID
    call dist_appendFormat(dist_fmtPartID, one)
  case("PARENT") ! Parent ID
    call dist_appendFormat(dist_fmtParentID, one)

  case("X") ! Horizontal position
    call dist_unitScale(fmtName, fmtUnit, 1, uFac, fErr)
    call dist_appendFormat(dist_fmtX, uFac)
  case("Y") ! Vertical positiom
    call dist_unitScale(fmtName, fmtUnit, 1, uFac, fErr)
    call dist_appendFormat(dist_fmtY, uFac)
  case("XP") ! Horizontal angle
    call dist_unitScale(fmtName, fmtUnit, 2, uFac, fErr)
    call dist_appendFormat(dist_fmtXP, uFac)
  case("YP") ! Vertical angle
    call dist_unitScale(fmtName, fmtUnit, 2, uFac, fErr)
    call dist_appendFormat(dist_fmtYP, uFac)
  case("PX") ! Horizontal momentum
    call dist_unitScale(fmtName, fmtUnit, 3, uFac, fErr)
    call dist_appendFormat(dist_fmtPX, uFac)
  case("PY") ! Vertical momentum
    call dist_unitScale(fmtName, fmtUnit, 3, uFac, fErr)
    call dist_appendFormat(dist_fmtPY, uFac)
  case("SIGMA","DS") ! Longitudinal relative position
    call dist_unitScale(fmtName, fmtUnit, 1, uFac, fErr)
    call dist_appendFormat(dist_fmtSIGMA, uFac)
  case("DT") ! Time delay
    call dist_unitScale(fmtName, fmtUnit, 4, uFac, fErr)
    call dist_appendFormat(dist_fmtDT, uFac)
  case("E") ! Particle energy
    call dist_unitScale(fmtName, fmtUnit, 3, uFac, fErr)
    call dist_appendFormat(dist_fmtE, uFac)
  case("P") ! Particle momentum
    call dist_unitScale(fmtName, fmtUnit, 3, uFac, fErr)
    call dist_appendFormat(dist_fmtP, uFac)
  case("DE/E0","DEE0") ! Relative particle energy (to reference particle)
    call dist_appendFormat(dist_fmtDEE0, one)
  case("DP/P0","DPP0") ! Relative particle momentum (to reference particle)
    call dist_appendFormat(dist_fmtDPP0, one)

  case("X_NORM") ! Normalised horizontal position
    call dist_appendFormat(dist_fmtX_NORM, one)
  case("Y_NORM") ! Normalised vertical positiom
    call dist_appendFormat(dist_fmtY_NORM, one)
  case("XP_NORM") ! Normalised horizontal angle
    call dist_appendFormat(dist_fmtXP_NORM, one)
  case("YP_NORM") ! Normalised vertical angle
    call dist_appendFormat(dist_fmtYP_NORM, one)
  case("PX_NORM") ! Normalised horizontal momentum
    call dist_appendFormat(dist_fmtPX_NORM, one)
  case("PY_NORM") ! Normalised vertical momentum
    call dist_appendFormat(dist_fmtPY_NORM, one)
  case("SIGMA_NORM","DS_NORM") ! Normalised longitudinal relative position
    call dist_appendFormat(dist_fmtSIGMA_NORM, one)
  case("DT_NORM") ! Normalised time delay
    call dist_appendFormat(dist_fmtDT_NORM, one)
  case("E_NORM") ! Normalised particle energy
    call dist_appendFormat(dist_fmtE_NORM, one)
  case("P_NORM") ! Normalised particle momentum
    call dist_appendFormat(dist_fmtP_NORM, one)
  case("DE/E0_NORM","DEE0_NORM") ! Normalised relative particle energy (to reference particle)
    call dist_appendFormat(dist_fmtDEE0_NORM, one)
  case("DP/P0_NORM","DPP0_NORM") ! Normalised relative particle momentum (to reference particle)
    call dist_appendFormat(dist_fmtDPP0_NORM, one)

  case("MASS","M") ! Particle mass
    call dist_unitScale(fmtName, fmtUnit, 3, uFac, fErr)
    call dist_appendFormat(dist_fmtMASS, uFac)
  case("CHARGE","Q") ! Particle charge
    call dist_appendFormat(dist_fmtCHARGE, one)
  case("ION_A") ! Ion atomic mass
    call dist_appendFormat(dist_fmtIonA, one)
  case("ION_Z") ! Ion atomic number
    call dist_appendFormat(dist_fmtIonZ, one)
  case("PDGID") ! Particle PDG ID
    call dist_appendFormat(dist_fmtPDGID, one)

  case("DEFAULT_4D") ! 4D default coordinates
    call dist_appendFormat(dist_fmtX, one)          ! Horizontal position
    call dist_appendFormat(dist_fmtY, one)          ! Vertical positiom
    call dist_appendFormat(dist_fmtXP, one)         ! Horizontal angle
    call dist_appendFormat(dist_fmtYP, one)         ! Vertical angle

  case("DEFAULT_6D") ! 6D default coordinates
    call dist_appendFormat(dist_fmtX, one)          ! Horizontal position
    call dist_appendFormat(dist_fmtY, one)          ! Vertical positiom
    call dist_appendFormat(dist_fmtXP, one)         ! Horizontal angle
    call dist_appendFormat(dist_fmtYP, one)         ! Vertical angle
    call dist_appendFormat(dist_fmtSIGMA, one)      ! Longitudinal relative position
    call dist_appendFormat(dist_fmtDPP0, one)       ! Relative particle momentum (to reference particle)

  case("DEFAULT_4D_NORM") ! 4D normalised coordinates
    call dist_appendFormat(dist_fmtX_NORM, one)     ! Normalised horizontal position
    call dist_appendFormat(dist_fmtY_NORM, one)     ! Normalised vertical positiom
    call dist_appendFormat(dist_fmtXP_NORM, one)    ! Normalised horizontal angle
    call dist_appendFormat(dist_fmtYP_NORM, one)    ! Normalised vertical angle

  case("DEFAULT_6D_NORM") ! 6D normalised coordinates
    call dist_appendFormat(dist_fmtX_NORM, one)     ! Normalised horizontal position
    call dist_appendFormat(dist_fmtY_NORM, one)     ! Normalised vertical positiom
    call dist_appendFormat(dist_fmtXP_NORM, one)    ! Normalised horizontal angle
    call dist_appendFormat(dist_fmtYP_NORM, one)    ! Normalised vertical angle
    call dist_appendFormat(dist_fmtSIGMA_NORM, one) ! Normalised longitudinal relative position
    call dist_appendFormat(dist_fmtDPP0_NORM, one)  ! Normalised relative particle momentum (to reference particle)

  case("IONS") ! The ion columns
    call dist_appendFormat(dist_fmtMASS, c1e3)      ! Particle mass
    call dist_appendFormat(dist_fmtCHARGE, one)     ! Particle charge
    call dist_appendFormat(dist_fmtIonA, one)       ! Ion atomic mass
    call dist_appendFormat(dist_fmtIonZ, one)       ! Ion atomic number
    call dist_appendFormat(dist_fmtPDGID, one)      ! Particle PDG ID

  case("OLD_DIST") ! The old DIST block file format
    call dist_appendFormat(dist_fmtPartID, one)     ! Particle ID
    call dist_appendFormat(dist_fmtNONE, one)       ! Ignored
    call dist_appendFormat(dist_fmtNONE, one)       ! Ignored
    call dist_appendFormat(dist_fmtX, c1e3)         ! Horizontal position
    call dist_appendFormat(dist_fmtY, c1e3)         ! Vertical positiom
    call dist_appendFormat(dist_fmtNONE, one)       ! Ignored
    call dist_appendFormat(dist_fmtXP, c1e3)        ! Horizontal angle
    call dist_appendFormat(dist_fmtYP, c1e3)        ! Vertical angle
    call dist_appendFormat(dist_fmtNONE, one)       ! Ignored
    call dist_appendFormat(dist_fmtIonA, one)       ! Ion atomic mass
    call dist_appendFormat(dist_fmtIonZ, one)       ! Ion atomic number
    call dist_appendFormat(dist_fmtMASS, c1e3)      ! Particle mass
    call dist_appendFormat(dist_fmtP, c1e3)         ! Particle momentum
    call dist_appendFormat(dist_fmtDT, one)         ! Time delay
  ! call dist_appendFormat(dist_fmtCHARGE, one)     ! Particle charge
  ! call dist_appendFormat(dist_fmtPDGID, one)      ! Particle PDG ID

  case default
    write(lerr,"(a)") "DIST> ERROR Unknown column format '"//trim(fmtName)//"'"
    fErr = .true.

  end select

end subroutine dist_setColumnFormat

! ================================================================================================ !
!  Parse File Column Units
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Created: 2019-07-05
!  Updated: 2019-07-08
! ================================================================================================ !
subroutine dist_unitScale(fmtName, fmtUnit, unitType, unitScale, uErr)

  use crcoall
  use string_tools
  use numerical_constants

  character(len=*), intent(in)    :: fmtName
  character(len=*), intent(in)    :: fmtUnit
  integer,          intent(in)    :: unitType
  real(kind=fPrec), intent(out)   :: unitScale
  logical,          intent(inout) :: uErr

  unitScale = zero

  if(unitType == 1) then ! Positions
    select case(chr_toLower(fmtUnit))
    case("[m]")
      unitScale = c1e3
    case("[mm]")
      unitScale = one
    case("[none]")
      unitScale = one
    case default
      goto 100
    end select
  elseif(unitType == 2) then ! Angle
    select case(chr_toLower(fmtUnit))
    case("[rad]")
      unitScale = c1e3
    case("[mrad]")
      unitScale = one
    case("[none]")
      unitScale = one
    case default
      goto 100
    end select
  elseif(unitType == 3) then ! Energy
    select case(chr_toLower(fmtUnit))
    case("[ev]")
      unitScale = c1m6
    case("[kev]")
      unitScale = c1m3
    case("[mev]")
      unitScale = one
    case("[gev]")
      unitScale = c1e3
    case("[tev]")
      unitScale = c1e6
    case("[none]")
      unitScale = one
    case default
      goto 100
    end select
  elseif(unitType == 4) then ! Time
    select case(chr_toLower(fmtUnit))
    case("[s]")
      unitScale = one
    case("[ms]")
      unitScale = c1e3
    case("[us]","[µs]")
      unitScale = c1e6
    case("[ns]")
      unitScale = c1e9
    case("[ps]")
      unitScale = c1e12
    case("[none]")
      unitScale = one
    case default
      goto 100
    end select
  end if

  return

100 continue
  write(lerr,"(a)") "DIST> ERROR Unrecognised or invalid unit for format identifier '"//trim(fmtName)//"'"
  uErr = .true.

end subroutine dist_unitScale

! ================================================================================================ !
!  Save File Column Format
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Created: 2019-07-05
!  Updated: 2019-07-05
! ================================================================================================ !
subroutine dist_appendFormat(fmtID, colScale)

  use mod_alloc
  use numerical_constants

  integer,          intent(in) :: fmtID
  real(kind=fPrec), intent(in) :: colScale

  dist_nColumns = dist_nColumns + 1

  call alloc(dist_colFormat, dist_nColumns, dist_fmtNONE, "dist_colFormat")
  call alloc(dist_colScale,  dist_nColumns, one,          "dist_colScale")

  dist_colFormat(dist_nColumns) = fmtID
  dist_colScale(dist_nColumns)  = colScale

end subroutine dist_appendFormat

subroutine dist_parseParticles

  use mod_common
  use string_tools

  character(len=:), allocatable :: lnSplit(:)
  integer i, j, nSplit
  logical spErr, cErr

  if(dist_numPart > 0) then
    do j=1,dist_numPart
      call chr_split(dist_partLine(j), lnSplit, nSplit, spErr)
      if(spErr) goto 20
      do i=2,nSplit
        call dist_saveParticle(j, i-1, lnSplit(i), cErr)
      end do
      if(cErr) goto 20
    end do
  end if

  return

20 continue
  write(lout,"(a,i0,a)") "DIST> ERROR Could not parse PARTICLE definition number ",j," from "//trim(fort3)

end subroutine dist_parseParticles

! ================================================================================================ !
!  A. Mereghetti and D. Sinuela Pastor, for the FLUKA Team
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Last modified: 2018-10-30
! ================================================================================================ !
subroutine dist_readDist

  use parpro
  use mod_common
  use mod_common_main
  use string_tools
  use mod_particles
  use numerical_constants
  use mod_units

  character(len=:), allocatable :: lnSplit(:)
  character(len=mInputLn) inLine
  integer i, j, nSplit, lineNo, fUnit
  logical spErr, cErr

  write(lout,"(a)") "DIST> Reading particles from '"//trim(dist_distFile)//"'"

  xv1(:)   = zero
  yv1(:)   = zero
  xv2(:)   = zero
  yv2(:)   = zero
  sigmv(:) = zero
  ejfv(:)  = zero
  ejf0v(:) = zero
  naa(:)   = 0
  nzz(:)   = 0
  nucm(:)  = zero

  lineNo = 0
  cErr   = .false.
  j      = dist_numPart ! PARTICLE definitions in the block are saved first

  if(dist_hasFormat .eqv. .false.) then
    call dist_setColumnFormat("OLD_DIST",cErr)
  end if

  call f_requestUnit(dist_distFile, fUnit)
  call f_open(unit=fUnit,file=dist_distFile,mode='r',err=cErr,formatted=.true.,status="old")
  if(cErr) goto 19

10 continue
  read(fUnit,"(a)",end=30,err=20) inLine
  lineNo = lineNo+1

  if(inLine(1:1) == "*") goto 10
  if(inLine(1:1) == "#") goto 10
  if(inLine(1:1) == "!") goto 10
  j = j+1

  if(j > napx) then
    write(lout,"(a,i0,a)") "DIST> Stopping reading file as ",napx," particles have been read, as requested in "//trim(fort3)
    j = napx
    goto 30
  end if

  call chr_split(inLine, lnSplit, nSplit, spErr)
  if(spErr) goto 20
  if(nSplit == 0) goto 10
  if(nSplit /= dist_nColumns) then
    write(lerr,"(2(a,i0))") "DIST> ERROR Number of columns in file on line ",lineNo,&
      " does not match format with ",dist_nColumns," columns"
    call prror
  end if
  do i=1,nSplit
    call dist_saveParticle(j, i, lnSplit(i), cErr)
  end do
  if(cErr) goto 20

  goto 10

19 continue
  write(lerr,"(a)") "DIST> ERROR Opening file '"//trim(dist_distFile)//"'"
  call prror
  return

20 continue
  write(lerr,"(a,i0)") "DIST> ERROR Reading particles from line ",lineNo
  call prror
  return

30 continue
  if(j == 0) then
    write(lerr,"(a)") "DIST> ERROR Reading particles. No particles read from file."
    call prror
    return
  end if

  call f_close(fUnit)
  write(lout,"(a,i0,a)") "DIST> Read ",j," particles from file '"//trim(dist_distFile)//"'"

  call dist_postprParticles(nSplit, cErr)

  ! Update longitudinal particle arrays from read momentum
  call part_updatePartEnergy(2)

  if(j < napx) then
    write(lout,"(a,i0)") "DIST> WARNING Read a number of particles LOWER than requested: ",napx
    napx = j
  end if

end subroutine dist_readDist

subroutine dist_saveParticle(partNo, colNo, inVal, sErr)

  use mod_common
  use mod_common_main
  use string_tools

  integer,          intent(in)    :: partNo
  integer,          intent(in)    :: colNo
  character(len=*), intent(in)    :: inVal
  logical,          intent(inout) :: sErr

  select case(dist_colFormat(colNo))

  case(dist_fmtNONE)
    return
  case(dist_fmtPartID)
    call chr_cast(inVal,partID(partNo),sErr)
  case(dist_fmtParentID)
    call chr_cast(inVal,parentID(partNo),sErr)

  case(dist_fmtX, dist_fmtX_NORM)
    call chr_cast(inVal, xv1(partNo), sErr)
    xv1(partNo) = xv1(partNo) * dist_colScale(colNo)
  case(dist_fmtY, dist_fmtY_NORM)
    call chr_cast(inVal, xv2(partNo), sErr)
    xv2(partNo) = xv2(partNo) * dist_colScale(colNo)
  case(dist_fmtXP, dist_fmtPX, dist_fmtXP_NORM, dist_fmtPX_NORM)
    call chr_cast(inVal, yv1(partNo), sErr)
    yv1(partNo) = yv1(partNo) * dist_colScale(colNo)
  case(dist_fmtYP, dist_fmtPY, dist_fmtYP_NORM, dist_fmtPY_NORM)
    call chr_cast(inVal, yv2(partNo), sErr)
    yv2(partNo) = yv2(partNo) * dist_colScale(colNo)

  case(dist_fmtSIGMA, dist_fmtDT, dist_fmtSIGMA_NORM, dist_fmtDT_NORM)
    call chr_cast(inVal, sigmv(partNo), sErr)
    sigmv(partNo) = sigmv(partNo) * dist_colScale(colNo)
  case(dist_fmtE, dist_fmtE_NORM)
    call chr_cast(inVal, ejv(partNo), sErr)
    ejv(partNo) = ejv(partNo) * dist_colScale(colNo)
  case(dist_fmtP, dist_fmtP_NORM)
    call chr_cast(inVal, ejfv(partNo), sErr)
    ejfv(partNo) = ejfv(partNo) * dist_colScale(colNo)
  case(dist_fmtDEE0, dist_fmtDEE0_NORM)
    call chr_cast(inVal, ejv(partNo), sErr)
    ejv(partNo) = ejv(partNo) * dist_colScale(colNo)
  case(dist_fmtDPP0, dist_fmtDPP0_NORM)
    call chr_cast(inVal, dpsv(partNo), sErr)

  case(dist_fmtMASS)
    call chr_cast(inVal, nucm(partNo), sErr)
    nucm(partNo) = nucm(partNo) * dist_colScale(colNo)
  case(dist_fmtCHARGE)
    call chr_cast(inVal, nqq(partNo), sErr)
  case(dist_fmtIonA)
    call chr_cast(inVal, naa(partNo), sErr)
  case(dist_fmtIonZ)
    call chr_cast(inVal, nzz(partNo), sErr)
! case(dist_fmtPDGID)
!   call chr_cast(inVal, pdgid(partNo), sErr)

  end select

end subroutine dist_saveParticle

subroutine dist_postprParticles(numCols, sErr)

  use mod_common
  use mod_common_main
  use numerical_constants
  use physical_constants

  integer, intent(in)    :: numCols
  logical, intent(inout) :: sErr

  integer i

  do i=1,numCols
    select case(dist_colFormat(i))

    case(dist_fmtPX)
      yv1(1:napx) = (yv1(1:napx)/ejfv(1:napx))*c1e3
    case(dist_fmtPY)
      yv2(1:napx) = (yv2(1:napx)/ejfv(1:napx))*c1e3
    case(dist_fmtDT)
      sigmv(1:napx) = -(e0f/e0)*(sigmv(1:napx)*clight)
    case(dist_fmtDEE0)
      ejv(1:napx) = (one + ejv(1:napx))*e0

    case(dist_fmtX_NORM)
      return
    case(dist_fmtY_NORM)
      return
    case(dist_fmtXP_NORM)
      return
    case(dist_fmtYP_NORM)
      return
    case(dist_fmtPX_NORM)
      return
    case(dist_fmtPY_NORM)
      return
    case(dist_fmtSIGMA_NORM)
      return
    case(dist_fmtDT_NORM)
      return
    case(dist_fmtE_NORM)
      return
    case(dist_fmtP_NORM)
      return
    case(dist_fmtDEE0_NORM)
      return
    case(dist_fmtDPP0_NORM)
      return

    end select
  end do

  mtc(1:napx)   = (nzz(1:napx)*nucm0)/(zz0*nucm(1:napx))
  pstop(1:napx) = .false.
  ejf0v(1:napx) = ejfv(1:napx)

end subroutine dist_postprParticles

! ================================================================================================ !
!  A. Mereghetti and D. Sinuela Pastor, for the FLUKA Team
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Last modified: 2018-10-31
! ================================================================================================ !
subroutine dist_finaliseDist

  use parpro
  use mod_common
  use mod_common_track
  use mod_common_main
  use numerical_constants

  implicit none

  integer          :: j
  real(kind=fPrec) :: chkP, chkE

  ! Check existence of on-momentum particles in the distribution
  do j=1, napx
    chkP = (ejfv(j)/nucm(j))/(e0f/nucm0)-one
    chkE = (ejv(j)/nucm(j))/(e0/nucm0)-one
    if(abs(chkP) < c1m15 .or. abs(chkE) < c1m15) then
      write(lout,"(a)")                "DIST> WARNING Encountered on-momentum particle."
      write(lout,"(a,4(1x,a25))")      "DIST>           ","momentum [MeV/c]","total energy [MeV]","Dp/p","1/(1+Dp/p)"
      write(lout,"(a,4(1x,1pe25.18))") "DIST> ORIGINAL: ", ejfv(j), ejv(j), dpsv(j), oidpsv(j)

      ejfv(j)     = e0f*(nucm(j)/nucm0)
      ejv(j)      = sqrt(ejfv(j)**2+nucm(j)**2)
      dpsv1(j)    = zero
      dpsv(j)     = zero
      oidpsv(j)   = one
      moidpsv(j)  = mtc(j)
      omoidpsv(j) = c1e3*(one-mtc(j))

      if(abs(nucm(j)/nucm0-one) < c1m15) then
        nucm(j) = nucm0
        if(nzz(j) == zz0 .or. naa(j) == aa0) then
          naa(j) = aa0
          nzz(j) = zz0
          mtc(j) = one
        else
          write(lerr,"(a)") "DIST> ERROR Mass and/or charge mismatch with relation to sync particle"
          call prror
        end if
      end if

      write(lout,"(a,4(1x,1pe25.18))") "DIST> CORRECTED:", ejfv(j), ejv(j), dpsv(j), oidpsv(j)
    end if
  end do

  write(lout,"(a,2(1x,i0),1x,f15.7)") "DIST> Reference particle species [A,Z,M]:", aa0, zz0, nucm0
  write(lout,"(a,1x,f15.7)")       "DIST> Reference energy [Z TeV]:", c1m6*e0/zz0

  do j=napx+1,npart
    partID(j)   = j
    parentID(j) = j
    pstop(j)    = .true.
    ejv(j)      = zero
    dpsv(j)     = zero
    oidpsv(j)   = one
    mtc(j)      = one
    naa(j)      = aa0
    nzz(j)      = zz0
    nucm(j)     = nucm0
    moidpsv(j)  = one
    omoidpsv(j) = zero
  end do

end subroutine dist_finaliseDist

! ================================================================================================ !
!  A. Mereghetti and D. Sinuela Pastor, for the FLUKA Team
!  V.K. Berglyd Olsen, BE-ABP-HSS
!  Last modified: 2018-10-30
! ================================================================================================ !
subroutine dist_echoDist

  use mod_common
  use mod_common_main
  use mod_units

  integer j, fUnit
  logical cErr

  call f_requestUnit(dist_echoFile, fUnit)
  call f_open(unit=fUnit,file=dist_echoFile,mode='w',err=cErr,formatted=.true.)
  if(cErr) goto 19

  rewind(fUnit)
  write(fUnit,"(a,1pe25.18)") "# Total energy of synch part [MeV]: ",e0
  write(fUnit,"(a,1pe25.18)") "# Momentum of synch part [MeV/c]:   ",e0f
  write(fUnit,"(a)")          "#"
  write(fUnit,"(a)")          "# x[mm], y[mm], xp[mrad], yp[mrad], sigmv[mm], ejfv[MeV/c]"
  do j=1, napx
    write(fUnit,"(6(1x,1pe25.18))") xv1(j), yv1(j), xv2(j), yv2(j), sigmv(j), ejfv(j)
  end do
  call f_close(fUnit)

  return

19 continue
  write(lerr,"(a)") "DIST> ERROR Opening file '"//trim(dist_echoFile)//"'"
  call prror
  return

end subroutine dist_echoDist

end module mod_dist

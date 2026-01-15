module MOM_test_case
  use pFUnit
  use MOM_coms_infra
  implicit none

  ! Template test case to auto init/finalize MOM infra for all inherited tests.
  type, extends(MpiTestCase) :: MOM_MPI_test_case
    contains
    procedure :: setUp => mom_setUp
    procedure :: tearDown => mom_tearDown
  end type MOM_MPI_test_case

contains

  ! Each call to init requires input.nml in the current working directory for FMS.
  subroutine mom_setUp(this)
    class (MOM_MPI_test_case), intent(inout) :: this
    call MOM_infra_init(this%getMpiCommunicator())
  end subroutine mom_setUp

  subroutine mom_tearDown(this)
    class (MOM_MPI_test_case), intent(inout) :: this
    call MOM_infra_end()
  end subroutine mom_tearDown

end module MOM_test_case
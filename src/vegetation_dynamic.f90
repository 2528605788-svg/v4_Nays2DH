module vegetation_dynamic_m
  implicit none
  private

  type, public :: vegetation_parameters
    logical :: enabled = .false.
    real(8) :: cycle_seconds = 90000.d0
    real(8) :: first_boundary_seconds = 90000.d0
    real(8) :: growth_multiplier = 1.d0
    real(8) :: recruitment_depth = 0.05d0
    real(8) :: initial_age = 1.d0
    real(8) :: allometry_age_limit = 30.d0
  end type vegetation_parameters

  type, public :: vegetation_state
    integer(4), allocatable :: presence(:,:), survived(:,:)
    real(8), allocatable :: age(:,:), effective_age(:,:)
    real(8), allocatable :: projected_density(:,:), height(:,:)
    real(8), allocatable :: root_depth(:,:), anchor_elevation(:,:)
    real(8), allocatable :: max_scour(:,:)
  end type vegetation_state

  public :: validate_vegetation_parameters, allocate_vegetation_state
  public :: initialize_vegetation_state, update_vegetation_scour
  public :: finish_vegetation_cycle, sync_vegetation_drag
  public :: vegetation_allometry

contains

  subroutine validate_vegetation_parameters(params, ok)
    type(vegetation_parameters), intent(in) :: params
    logical, intent(out) :: ok

    ok = params%cycle_seconds > 0.d0 .and. &
         params%first_boundary_seconds >= 0.d0 .and. &
         params%growth_multiplier > 0.d0 .and. &
         params%recruitment_depth >= 0.d0 .and. &
         params%initial_age > 0.d0 .and. &
         params%allometry_age_limit > 0.d0
  end subroutine validate_vegetation_parameters

  pure subroutine vegetation_allometry(age, params, effective_age, &
                                        projected_density, height, root_depth)
    real(8), intent(in) :: age
    type(vegetation_parameters), intent(in) :: params
    real(8), intent(out) :: effective_age, projected_density
    real(8), intent(out) :: height, root_depth
    real(8) :: y_eff, n_tree, d_cm

    if (age <= 0.d0) then
      effective_age = 0.d0
      projected_density = 0.d0
      height = 0.d0
      root_depth = 0.d0
      return
    end if

    y_eff = min(age * params%growth_multiplier, params%allometry_age_limit)
    n_tree = 1.52d0 * y_eff**(-0.63d0)
    d_cm = 0.11d0 * y_eff**1.77d0
    effective_age = y_eff
    projected_density = n_tree * d_cm / 100.d0
    height = 1.27d0 * d_cm**0.79d0
    root_depth = 28.9d0 * d_cm**0.23d0 / 100.d0
  end subroutine vegetation_allometry

  subroutine allocate_vegetation_state(state, nx, ny)
    type(vegetation_state), intent(inout) :: state
    integer, intent(in) :: nx, ny

    allocate(state%presence(0:nx,0:ny), state%survived(0:nx,0:ny))
    allocate(state%age(0:nx,0:ny), state%effective_age(0:nx,0:ny))
    allocate(state%projected_density(0:nx,0:ny))
    allocate(state%height(0:nx,0:ny), state%root_depth(0:nx,0:ny))
    allocate(state%anchor_elevation(0:nx,0:ny))
    allocate(state%max_scour(0:nx,0:ny))

    state%presence = 0
    state%survived = 0
    state%age = 0.d0
    state%effective_age = 0.d0
    state%projected_density = 0.d0
    state%height = 0.d0
    state%root_depth = 0.d0
    state%anchor_elevation = 0.d0
    state%max_scour = 0.d0
  end subroutine allocate_vegetation_state

  subroutine initialize_vegetation_state(state, params, initial_density, &
                                         bed_elevation, nx, ny)
    type(vegetation_state), intent(inout) :: state
    type(vegetation_parameters), intent(in) :: params
    real(8), intent(in) :: initial_density(:,:)
    real(8), intent(in) :: bed_elevation(0:,0:)
    integer, intent(in) :: nx, ny
    integer :: i, j

    do j = 1, ny
      do i = 1, nx
        state%anchor_elevation(i,j) = bed_elevation(i,j)
        if (initial_density(i,j) > 0.d0) then
          state%presence(i,j) = 1
          state%age(i,j) = params%initial_age
        end if
      end do
    end do
  end subroutine initialize_vegetation_state

  subroutine update_vegetation_scour(state, bed_elevation, nx, ny)
    type(vegetation_state), intent(inout) :: state
    real(8), intent(in) :: bed_elevation(0:,0:)
    integer, intent(in) :: nx, ny
    integer :: i, j

    do j = 1, ny
      do i = 1, nx
        if (state%presence(i,j) == 1) then
          state%max_scour(i,j) = max(state%max_scour(i,j), &
               state%anchor_elevation(i,j) - bed_elevation(i,j))
          if (state%max_scour(i,j) > state%root_depth(i,j)) then
            state%presence(i,j) = 0
            state%survived(i,j) = 0
            state%age(i,j) = 0.d0
            state%effective_age(i,j) = 0.d0
            state%projected_density(i,j) = 0.d0
            state%height(i,j) = 0.d0
            state%root_depth(i,j) = 0.d0
          end if
        end if
      end do
    end do
  end subroutine update_vegetation_scour

  subroutine finish_vegetation_cycle(state, params, bed_elevation, &
                                     water_depth, nx, ny)
    type(vegetation_state), intent(inout) :: state
    type(vegetation_parameters), intent(in) :: params
    real(8), intent(in) :: bed_elevation(0:,0:), water_depth(0:,0:)
    integer, intent(in) :: nx, ny
    integer :: i, j

    do j = 1, ny
      do i = 1, nx
        if (state%presence(i,j) == 1) then
          state%age(i,j) = state%age(i,j) + 1.d0
          state%survived(i,j) = 1
        else if (water_depth(i,j) <= params%recruitment_depth) then
          state%presence(i,j) = 1
          state%survived(i,j) = 0
          state%age(i,j) = 1.d0
        end if
        state%anchor_elevation(i,j) = bed_elevation(i,j)
        state%max_scour(i,j) = 0.d0
      end do
    end do
  end subroutine finish_vegetation_cycle

  subroutine sync_vegetation_drag(state, params, c_tree, cd_veg, vege_h, &
                                  nx, ny)
    type(vegetation_state), intent(inout) :: state
    type(vegetation_parameters), intent(in) :: params
    real(8), intent(in) :: c_tree
    real(8), intent(inout) :: cd_veg(0:,0:), vege_h(0:,0:)
    integer, intent(in) :: nx, ny
    integer :: i, j

    do j = 0, ny
      do i = 0, nx
        if (state%presence(i,j) == 1) then
          call vegetation_allometry(state%age(i,j), params, &
               state%effective_age(i,j), state%projected_density(i,j), &
               state%height(i,j), state%root_depth(i,j))
          cd_veg(i,j) = 0.5d0 * c_tree * state%projected_density(i,j)
          vege_h(i,j) = state%height(i,j)
        else
          state%effective_age(i,j) = 0.d0
          state%projected_density(i,j) = 0.d0
          state%height(i,j) = 0.d0
          state%root_depth(i,j) = 0.d0
          cd_veg(i,j) = 0.d0
          vege_h(i,j) = 0.d0
        end if
      end do
    end do
  end subroutine sync_vegetation_drag

end module vegetation_dynamic_m

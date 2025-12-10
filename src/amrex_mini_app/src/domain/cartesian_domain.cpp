#include <cstddef>

#include <AMReX.H>

#include "geometry.h" // TODO: Replace with cartesian_geometry.h when it is seperated out of geometry.h
#include "cartesian_grid.h"
#include "field.h"
#include "field_container.h"
#include "domain.h"
#include "cartesian_domain.h"

namespace turbo {


CartesianDomain::CartesianDomain(double x_min, double x_max,
               double y_min, double y_max,
               double z_min, double z_max,
               std::size_t n_cell_x,
               std::size_t n_cell_y,
               std::size_t n_cell_z)
    : Domain(
        std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max),
        std::make_shared<CartesianGrid>(
            std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max),
            n_cell_x,
            n_cell_y,
            n_cell_z)
      )
{
    // Constructor body (if needed)
}

    //Domain::Domain(const std::shared_ptr<Grid>& grid)
    //    : geometry_(grid->geometry()), grid_(grid), field_container_(std::make_shared<FieldContainer>(grid))
    //{
    //    static_assert(
    //        amrex::SpaceDim == 3,
    //        "Only supports 3D grids."
    //    );
    //
    //    if (!geometry_) {
    //        throw std::invalid_argument("Domain constructor: geometry pointer is null");
    //    }
    //
    //    if (!grid_) {
    //        throw std::invalid_argument("Domain constructor: grid pointer is null");
    //    }
    //
    //    // number of ghost cells
    //    const int n_ghost = 1; // Maybe we dont want ghost elements for some of the MultiFabs, or only in certain directions, but I just setting it the same for all of them for now.
    //
    //    // number of components for each type of MultiFab
    //    const int n_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
    //    const int n_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)
    //}
//    const int n_ghost = 1; // Maybe we dont want ghost elements for some of the MultiFabs, or only in certain directions, but I just setting it the same for all of them for now.
//
//    // number of components for each type of MultiFab
//    const int n_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
//    const int n_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)
//
//
//}

} // namespace turbo
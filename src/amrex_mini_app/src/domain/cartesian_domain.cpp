#include <cstddef>
#include <memory>

#include <AMReX.H>

#include "cartesian_domain.h"
#include "domain.h"
#include "cartesian_geometry.h" 
#include "cartesian_grid.h"
#include "field.h"

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

}

} // namespace turbo
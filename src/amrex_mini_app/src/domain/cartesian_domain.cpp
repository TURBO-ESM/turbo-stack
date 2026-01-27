#include <cstddef>
#include <memory>

#include "domain.h"
#include "cartesian_domain.h"
#include "cartesian_geometry.h" 
#include "cartesian_grid.h"

namespace turbo {

CartesianDomain::CartesianDomain(double x_min, double x_max,
               double y_min, double y_max,
               double z_min, double z_max,
               std::size_t n_cell_x,
               std::size_t n_cell_y,
               std::size_t n_cell_z)
    : Domain(
        std::make_shared<CartesianGrid>(
            std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max),
            n_cell_x,
            n_cell_y,
            n_cell_z)
      )
{
}

std::shared_ptr<CartesianGeometry> CartesianDomain::GetGeometry() const noexcept {
    return std::static_pointer_cast<CartesianGeometry>(grid_->GetGeometry());
}

std::shared_ptr<CartesianGrid> CartesianDomain::GetGrid() const noexcept {
    return std::static_pointer_cast<CartesianGrid>(grid_);
}

} // namespace turbo

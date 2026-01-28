#pragma once

#include <cstddef>
#include <memory>

#include "domain.h"
#include "cartesian_geometry.h" 
#include "cartesian_grid.h"

namespace turbo {

class CartesianDomain : public Domain {

public:
    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Construct a CartesianDomain with the given extents and cell counts.
     * @param x_min Minimum x-coordinate
     * @param x_max Maximum x-coordinate
     * @param y_min Minimum y-coordinate
     * @param y_max Maximum y-coordinate
     * @param z_min Minimum z-coordinate
     * @param z_max Maximum z-coordinate
     * @param n_cell_x Number of cells in X direction
     * @param n_cell_y Number of cells in Y direction
     * @param n_cell_z Number of cells in Z direction
     */
    CartesianDomain(double x_min, double x_max,
           double y_min, double y_max,
           double z_min, double z_max,
           std::size_t n_cell_x,
           std::size_t n_cell_y,
           std::size_t n_cell_z);

    /**
     * @brief Get the geometry associated with the Cartesian domain.
     * @return Shared pointer to CartesianGeometry.
     */
    std::shared_ptr<CartesianGeometry> GetGeometry() const noexcept;

    /**
     * @brief Get the grid associated with the Cartesian domain.
     * @return Shared pointer to CartesianGrid.
     */
    std::shared_ptr<CartesianGrid> GetGrid() const noexcept;

};

} // namespace turbo

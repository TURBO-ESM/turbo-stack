#pragma once

#include <cstddef>
#include <memory>

#include "domain.h"
#include "cartesian_domain.h"
#include "cartesian_geometry.h" 
#include "cartesian_grid.h"

namespace turbo {

class CartesianDomain : public Domain {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    CartesianDomain(double x_min, double x_max,
           double y_min, double y_max,
           double z_min, double z_max,
           std::size_t n_cell_x,
           std::size_t n_cell_y,
           std::size_t n_cell_z);

    // Accessors
    std::shared_ptr<CartesianGeometry> GetGeometry() const noexcept { 
        return std::static_pointer_cast<CartesianGeometry>(geometry_);
    }

    std::shared_ptr<CartesianGrid> GetGrid() const noexcept { 
        return std::static_pointer_cast<CartesianGrid>(grid_);
    }

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//


private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};

} // namespace turbo
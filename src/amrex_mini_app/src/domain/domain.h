#pragma once

#include <memory>
#include <string>

#include "geometry.h"
#include "grid.h"
#include "field.h"
#include "field_container.h"

namespace turbo {

class Domain {
public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    // Constructors
    // There should be a way to get the geometry from the grid, so maybe only pass in the grid when we get that worked out.
    Domain(const std::shared_ptr<Geometry>& geometry, const std::shared_ptr<Grid>& grid);

    /**
     * @brief Virtual destructor for Domain.
     */
    virtual ~Domain() = default;

    // Accessors
    std::shared_ptr<Geometry> GetGeometry() const noexcept { return geometry_; }
    std::shared_ptr<Grid> GetGrid() const noexcept { return grid_; }
    std::shared_ptr<FieldContainer> GetFields() const noexcept { return fields_; }

    /**
     * @brief Write the domain data to an HDF5 file.
     * @param filename Name of the HDF5 file to write.
     */
    void WriteHDF5(const std::string& filename) const ;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//

protected:
    /**
     * @brief Shared pointer to the geometry associated with the domain.
     */
    const std::shared_ptr<Geometry> geometry_;

    /**
     * @brief Shared pointer to the grid associated with the domain.
     */
    const std::shared_ptr<Grid> grid_;

    /**
     * @brief Shared pointer to the field container holding the domain's fields.
     */
    const std::shared_ptr<FieldContainer> fields_;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};


} // namespace turbo
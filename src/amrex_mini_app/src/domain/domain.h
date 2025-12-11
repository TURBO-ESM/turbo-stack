#pragma once

#include <memory>
#include <string>
#include <set>

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
    std::shared_ptr<Geometry> GetGeometry() const noexcept;
    std::shared_ptr<Grid> GetGrid() const noexcept;
    std::set<std::shared_ptr<Field>> GetFields() const noexcept;

    /**
     * @brief Create a field to the domain's field container.
     * @param name Name of the field.
     * @param stagger Field grid staggering type.
     * @param n_component Number of components (e.g., 1 for scalar fields).
     * @param n_ghost Number of ghost cells.
     * @return Shared pointer to the newly created field.
     * @throws std::invalid_argument if invalid input (name already exists in container, invalid number of components or
     * ghost cells, invalid stagger type, etc.).
     * @throws std::logic_error if the field cannot be inserted into the container given valid input.   
     */
    std::shared_ptr<Field> CreateField(const Field::NameType& field_name, const FieldGridStagger stagger,
                                       const std::size_t n_component, const std::size_t n_ghost);

    /**
     * @brief Get a field by name from the domain's field container.
     * @param name Name of the field to retrieve.
     * @return Shared pointer to the Field.
     * @throws std::invalid_argument if the field does not exist.
     */
    std::shared_ptr<Field> GetField(const Field::NameType& field_name) const;

    /**
     * @brief Check if a field with the given name exists in the domain's field container.
     * @param field_name Name of the field to check.
     * @return true if the field exists, false otherwise.
     */
    bool HasField(const Field::NameType& field_name) const;

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
    const std::shared_ptr<FieldContainer> field_container_;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//

};


} // namespace turbo
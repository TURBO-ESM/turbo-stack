#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <ranges>
#include <map>
#include <stdexcept>

#include "geometry.h"
#include "grid.h"
#include "field.h"

namespace turbo {

class Domain {
 public:

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Constructor for Domain.
     * @param grid Shared pointer to the Grid associated with the domain.
     */
    Domain(const std::shared_ptr<Grid>& grid);

    /**
     * @brief Virtual destructor for Domain.
     */
    virtual ~Domain() = default;

    /**
     * @brief Get the geometry associated with the domain.
     * @return Shared pointer to the Geometry.
     */
    std::shared_ptr<Geometry> GetGeometry() const noexcept;  // TODO: Maybe dont need this function if we can always get the geometry from the grid?
    // Maybe have grid not be commited to supporting geometry at some point in the future? That way some grids could not tied to a geometry object?

    /**
     * @brief Get the grid associated with the domain.
     * @return Shared pointer to the Grid.
     */
    std::shared_ptr<Grid> GetGrid() const noexcept;

    /**
     * @brief Get a view of all fields in the domain's field container.
     * @return A range view of shared pointers to Fields.
     */
    // Have to inline the definition in the header file so that the return type can be deduced properly by auto
    std::ranges::view auto GetFields() const noexcept { return std::views::values(field_container_); }

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

 protected:

    /**
     * @brief Shared pointer to the grid associated with the domain.
     */
    const std::shared_ptr<Grid> grid_;

    /**
     * @brief Container for the fields defined on the domain.
     */
    std::map<Field::NameType, std::shared_ptr<Field>> field_container_;

};

} // namespace turbo
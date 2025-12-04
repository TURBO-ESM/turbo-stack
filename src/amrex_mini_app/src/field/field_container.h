#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <tuple>
#include <map>
#include <stdexcept>

#include "grid.h"
#include "field.h"

namespace turbo {

/**
 * @class FieldContainer
 * @brief Manages a collection of Field objects associated with a single Grid.
 *
 * FieldContainer provides insertion, lookup, and iteration for fields defined on a grid.
 * It ensures that all fields share the same grid and supports const-only iteration.
 */
class FieldContainer {

    // Some private type aliases for convenience. For the underlying container used to store the fields.
    using FieldKey = std::tuple<Field::NameType, FieldGridStagger>;
    using FieldMap = std::map<FieldKey, std::shared_ptr<Field>>;

public:

    //-----------------------------------------------------------------------//
    // Public Member Types
    //-----------------------------------------------------------------------//

    /**
     * @brief Const iterator type for iterating over fields.
     */
    using const_iterator = FieldMap::const_iterator;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Construct a FieldContainer for a given grid.
     * @param grid Shared pointer to the grid for all fields in this container.
     */
    FieldContainer(const std::shared_ptr<Grid>& grid);

    /**
     * @brief Check if a field with the given name exists in the container.
     * @param name Name of the field to check.
     * @return true if the field exists, false otherwise.
     */
    bool Contains(const Field::NameType& name, const FieldGridStagger stagger) const noexcept;

    /**
     * @brief Insert a new field into the container.
     * @param name Name of the field.
     * @param stagger Field grid staggering type.
     * @param n_component Number of components (e.g., 1 for scalar fields).
     * @param n_ghost Number of ghost cells.
     * @return Shared pointer to the inserted Field.
     * @throws std::invalid_argument if invalid input (name already exists in container, invalid number of components or ghost cells, invalid stagger type, etc.).
     * @throws std::logic_error if the field cannot be inserted into the container given valid input.
     */
    std::shared_ptr<Field> Insert(const Field::NameType& name, const FieldGridStagger stagger, const std::size_t n_component, const std::size_t n_ghost);

    /**
     * @brief Get a field by name and stagger.
     * @param name Name of the field to retrieve.
     * @param stagger Field grid staggering type.
     * @return Shared pointer to the Field.
     * @throws std::invalid_argument if the field does not exist in the container.
     */
    std::shared_ptr<Field> Get(const Field::NameType& name, const FieldGridStagger stagger) const;

    /**
     * @brief Get a const iterator to the beginning of the fields set.
     * @return Const iterator to the first field.
     */
    const_iterator begin() const;

    /**
     * @brief Get a const iterator to the end of the fields set.
     * @return Const iterator to one past the last field.
     */
    const_iterator end() const;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//

    /**
     * @brief Shared pointer to the grid for all fields in this container.
     */
    const std::shared_ptr<Grid> grid_;

    /**
     * @brief Set of shared pointers to Field objects managed by this container.
     */
    FieldMap field_map;

};

} // namespace turbo
#pragma once

#include <cstddef>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <tuple>
#include <ranges>
#include <utility>

#include "field.h"
#include "grid.h"

namespace turbo
{

/**
 * @class FieldContainer
 * @brief Manages a collection of Field objects associated with a single Grid.
 *
 * FieldContainer provides insertion, lookup, and iteration for fields defined on a grid.
 * It ensures that all fields in the container are on the same grid.
 * Each field has a unique combination of name and stagger.
 */
class FieldContainer
{
    //-----------------------------------------------------------------------//
    // Some private type aliases for convenience.
    //-----------------------------------------------------------------------//
    using FieldKey = std::tuple<Field::NameType, FieldGridStagger>;
    using FieldMap = std::map<FieldKey, std::shared_ptr<Field>>;

   public:
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
     * @brief Construct a new field and insert it into the container.
     * @param name Name of the field.
     * @param stagger Field grid staggering type.
     * @param n_component Number of components (e.g., 1 for scalar fields).
     * @param n_ghost Number of ghost cells.
     * @return Shared pointer to the newly created field.
     * @throws std::invalid_argument if invalid input (name already exists in container, invalid number of components or
     * ghost cells, invalid stagger type, etc.).
     * @throws std::logic_error if the field cannot be inserted into the container given valid input.
     */
    std::shared_ptr<Field> Insert(const Field::NameType& name, const FieldGridStagger stagger,
                                  const std::size_t n_component, const std::size_t n_ghost);

    /**
     * @brief Get a field by name and stagger.
     * @param name Name of the field to retrieve.
     * @param stagger Field grid staggering type.
     * @return Shared pointer to the Field.
     * @throws std::invalid_argument if the field does not exist in the container.
     */
    std::shared_ptr<Field> Get(const Field::NameType& name, const FieldGridStagger stagger) const;

    /**
     * @brief Get an iterator to the beginning of the field values (C++20 views).
     * @return Iterator to the first field.
     */

    auto begin() const -> decltype(std::views::values(std::declval<const FieldMap&>()).begin());

    /**
     * @brief Get an iterator to the end of the field values (C++20 views).
     * @return Iterator to one past the last field.
     */
    auto end() const -> decltype(std::views::values(std::declval<const FieldMap&>()).end());

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

}  // namespace turbo
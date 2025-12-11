#include "field_container.h"

#include <cstddef>
#include <map>
#include <memory>
#include <stdexcept>
#include <tuple>
#include <ranges>

#include "field.h"
#include "grid.h"

namespace turbo
{

FieldContainer::FieldContainer(const std::shared_ptr<Grid>& grid) : grid_(grid)
{
    if (!grid_)
    {
        throw std::invalid_argument("FieldContainer::FieldContainer: grid pointer is null");
    }
}

bool FieldContainer::Contains(const Field::NameType& name) const noexcept
{
    return field_map.contains(name);
}

std::shared_ptr<Field> FieldContainer::Insert(const Field::NameType& name, const FieldGridStagger field_grid_stagger,
                                              const std::size_t n_component, const std::size_t n_ghost)
{
    if (Contains(name))
    {
        throw std::invalid_argument("FieldContainer::Insert: Field with name '" + name + "' already exists.");
    }

    const std::shared_ptr<Field> field = std::make_shared<Field>(name, grid_, field_grid_stagger, n_component, n_ghost);
    auto [iter, inserted]              = field_map.insert({name, field});
    if (!inserted)
    {
        // Since we already checked that no value with this same key exist in the map, we should never reach this point.
        // The insert should always succeed.
        throw std::logic_error(
            "FieldContainer::Insert: Failed to insert field. Somehow it was not inserted into the map used under the "
            "hood of field container. Should never happen.");
    }

    return field;
}

std::shared_ptr<Field> FieldContainer::Get(const Field::NameType& name) const
{
    auto it = field_map.find(name);
    if (it != field_map.end())
    {
        return it->second;
    }
    // Maybe we want to do something else instead of throwing an exception here?
    throw std::invalid_argument("FieldContainer::Get: Field with name '" + name + "' does not exist.");
}

auto FieldContainer::begin() const -> decltype(std::views::values(std::declval<const FieldMap&>()).begin()) 
{
    return std::views::values(field_map).begin();
}

auto FieldContainer::end() const -> decltype(std::views::values(std::declval<const FieldMap&>()).end()) 
{
    return std::views::values(field_map).end();
}

}  // namespace turbo
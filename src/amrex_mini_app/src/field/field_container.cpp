#include <cstddef>
#include <memory>
#include <string>
#include <set>
#include <stdexcept>

#include "grid.h"
#include "field.h"
#include "field_container.h"

namespace turbo {

FieldContainer::FieldContainer(const std::shared_ptr<Grid>& grid)
: grid_(grid)
{
    if (!grid_) {
        throw std::invalid_argument("FieldContainer::FieldContainer: grid pointer is null");
    }
}

bool FieldContainer::Contains(const std::string& name) const noexcept {
    for (const std::shared_ptr<Field>& field : fields_) {
        if (field->name == name) {
            return true;
        }
    }
    return false;
}

std::shared_ptr<Field> FieldContainer::Insert(const std::string& name, const FieldGridStagger field_grid_stagger, std::size_t n_component, std::size_t n_ghost) {
    for (const std::shared_ptr<Field>& field : fields_) {
        if (field->name == name) {
            throw std::invalid_argument("FieldContainer::Insert: Field with name '" + name + "' already exists.");
        }
    }

    const std::shared_ptr<Field> field = std::make_shared<Field>(name, grid_, field_grid_stagger, n_component, n_ghost);
    auto [iter, inserted] = fields_.insert(field);
    if (!inserted) {
        // Since we already checked that no fields with this same name exist in the set, we should never reach this point. The insert should always succeed.
        throw std::logic_error("FieldContainer::Insert: Failed to insert field. Somehow it was not inserted into the set. Should never happen.");
    }

    return field;
}

std::shared_ptr<Field> FieldContainer::Get(const std::string& name) const {
    for (const std::shared_ptr<Field>& field : fields_) {
        if (field->name == name) {
            return field;
        }
    }
    // Maybe we want to do something else instead of throwing an exception here? T
    throw std::invalid_argument("FieldContainer::Get: Field with name '" + name + "' does not exist.");
}

FieldContainer::const_iterator FieldContainer::begin() const { return fields_.begin(); }
FieldContainer::const_iterator FieldContainer::end() const { return fields_.end(); }

} // namespace turbo
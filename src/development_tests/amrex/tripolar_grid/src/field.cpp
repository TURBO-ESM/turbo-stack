#include <cstddef>
#include <memory>
#include <string>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <hdf5.h>

#include "grid.h"
#include "field.h"

namespace turbo {

FieldContainer::FieldContainer(const std::shared_ptr<Grid>& grid)
: grid_(grid)
{
    if (!grid_) {
        throw std::invalid_argument("Field constructor: grid pointer is null");
    }
}

std::shared_ptr<Field> FieldContainer::Insert(const std::string& name, const FieldGridStagger field_grid_stagger, std::size_t n_component, std::size_t n_ghost) {
    for (const std::shared_ptr<Field>& field : fields_) {
        if (field->name == name) {
            throw std::invalid_argument("FieldContainer::Insert: Field with name '" + name + "' already exists.");
        }
    }

    if (n_component <= 0) {
    throw std::invalid_argument("FieldContainer::Insert: Number of components must be greater than zero.");
    }

    if (n_ghost < 0) {
    throw std::invalid_argument("FieldContainer::Insert: Number of ghost cells cannot be negative.");
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

void FieldContainer::WriteHDF5(const hid_t file_id) const {
    for (const auto& field : fields_) {
        field->WriteHDF5(file_id);
    }
}


} // namespace turbo
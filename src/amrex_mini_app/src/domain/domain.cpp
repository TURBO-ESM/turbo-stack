#include <cstddef>
#include <string>
#include <memory>
#include <stdexcept>

#include <hdf5.h>

#include <AMReX.H>

#include "domain.h"
#include "geometry.h"
#include "grid.h"
#include "field.h"

namespace turbo {

Domain::Domain(const std::shared_ptr<Grid>& grid)
                : grid_(grid), field_container_({}) {}

std::shared_ptr<Geometry> Domain::GetGeometry() const noexcept { return grid_->GetGeometry(); }

std::shared_ptr<Grid> Domain::GetGrid() const noexcept { return grid_; }

std::shared_ptr<Field> Domain::CreateField(const Field::NameType& name, const FieldGridStagger stagger,
                                       const std::size_t n_component, const std::size_t n_ghost)
{
    if (field_container_.contains(name))
    {
        throw std::invalid_argument("Domain::CreateField failed because field with name '" + name + "' already exists.");
    }

    const std::shared_ptr<Field> field = std::make_shared<Field>(name, grid_, stagger, n_component, n_ghost);
    auto [iter, inserted]              = field_container_.insert({name, field});
    if (!inserted)
    {
        // Since we already checked that no value with this key exist in the map and created the field pointer,
        //  the insert should always succeed and we should never reach this point.
        throw std::logic_error(
            "Domain::CreateField failed to insert field. Somehow it was not inserted into the map used under the "
            "hood of Domain. This should never happen.");
    }

    return field;
}

std::shared_ptr<Field> Domain::GetField(const Field::NameType& name) const 
{
    auto it = field_container_.find(name);
    if (it != field_container_.end())
    {
        return it->second;
    }
    throw std::invalid_argument("Domain::GetField: Field with name '" + name + "' does not exist.");
}

bool Domain::HasField(const Field::NameType& field_name) const 
{
    return field_container_.contains(field_name);
}

void Domain::WriteHDF5(const std::string& filename) const {

    hid_t file_id;

    // Only the IOProcessor writes the grid information and metadata
    if (amrex::ParallelDescriptor::IOProcessor()) {

        file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);

        if (file_id < 0) {
            throw std::runtime_error("Failed to create HDF5 file: " + filename);
        }

        {
            double test_double_value = 1.0; // Example test double value, can be set to any value you want
            const hid_t attr_space_id = H5Screate(H5S_SCALAR);
            const hid_t attr_id = H5Acreate(file_id, "double_test_value", H5T_NATIVE_DOUBLE, attr_space_id, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, H5T_NATIVE_DOUBLE, &test_double_value);
            H5Aclose(attr_id);
            H5Sclose(attr_space_id);
        }

        {
            int test_int_value = 1; // Example test value, can be set to any value you want
            const hid_t attr_space_id = H5Screate(H5S_SCALAR);
            const hid_t attr_id = H5Acreate(file_id, "int_test_value", H5T_NATIVE_INT, attr_space_id, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, H5T_NATIVE_INT, &test_int_value);
            H5Aclose(attr_id);
            H5Sclose(attr_space_id);
        }

        GetGrid()->WriteHDF5(file_id);

    }

    for (const auto& field : GetFields()) {
        field->WriteHDF5(file_id);
    }

    if (amrex::ParallelDescriptor::IOProcessor()) {
        H5Fclose(file_id);
    }

}

} // namespace turbo
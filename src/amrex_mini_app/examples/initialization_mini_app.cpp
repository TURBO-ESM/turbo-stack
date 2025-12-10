#include <cstddef>
#include <memory>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "hdf5.h"

#include "geometry.h"
#include "cartesian_grid.h"
#include "field.h"
#include "field_container.h"

using namespace turbo;

void WriteHDF5(const std::string& filename, const std::shared_ptr<FieldContainer>& field_container) {

    hid_t file_id;

    // Only the IOProcessor writes the grid information and metadata
    if (amrex::ParallelDescriptor::IOProcessor()) {

        file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);

        if (file_id < 0) {
            throw std::runtime_error("Invalid HDF5 file_id passed to WriteHDF5.");
        }

        // Add an attribute to specify the data layout of the following datasets (row-major or column-major)
        {
            const char* layout = "row-major";
            const hid_t str_type = H5Tcopy(H5T_C_S1);
            H5Tset_size(str_type, strlen(layout) + 1); // +1 for the null terminator
    
            const hid_t attr_space_id = H5Screate(H5S_SCALAR);
            const hid_t attr_id = H5Acreate(file_id, "data_layout", str_type, attr_space_id, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, str_type, layout);
            H5Aclose(attr_id);
            H5Sclose(attr_space_id);
            H5Tclose(str_type);        
        }

        // Example test double value, can be set to any value you want... might be useful for to attach time step size, current time, etc.
        {
            double test_double_value = 1.0; 
            const hid_t attr_space_id = H5Screate(H5S_SCALAR);
            const hid_t attr_id = H5Acreate(file_id, "double_test_value", H5T_NATIVE_DOUBLE, attr_space_id, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, H5T_NATIVE_DOUBLE, &test_double_value);
            H5Aclose(attr_id);
            H5Sclose(attr_space_id);
        }

        // Example test scalar value, can be set to any value you want... might be useful for to attach time step, iteration number, etc.
        {
            int test_int_value = 1; 
            const hid_t attr_space_id = H5Screate(H5S_SCALAR);
            const hid_t attr_id = H5Acreate(file_id, "int_test_value", H5T_NATIVE_INT, attr_space_id, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, H5T_NATIVE_INT, &test_int_value);
            H5Aclose(attr_id);
            H5Sclose(attr_space_id);
        }

        for (auto field :*field_container) {
            // Kind of hacky but we know that all the fields in the container share the same grid, so we can just take the first one.
            field->grid->WriteHDF5(file_id);
            break; 
        }
    }

    // Fields know how to write themselves to HDF5. Will automatically choose the right process to write based on AMReX parallel settings.
    for (const auto& field : *field_container) {
        field->WriteHDF5(file_id);
    }

    if (amrex::ParallelDescriptor::IOProcessor()) {
        H5Fclose(file_id);
    }
}

int main(int argc, char* argv[])
{
    amrex::Initialize(argc, argv);
    {
        std::shared_ptr<CartesianGeometry> geometry;
        {
            const double x_min = 0.0;
            const double x_max = 1.0;
            const double y_min = 0.0;
            const double y_max = 1.0;
            const double z_min = 0.0;
            const double z_max = 1.0;
            geometry = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);
        }

        std::shared_ptr<CartesianGrid> grid;
        {
            const std::size_t n_cell_x = 4;
            const std::size_t n_cell_y = 8;
            const std::size_t n_cell_z = 16;
            grid = std::make_shared<CartesianGrid>(geometry, n_cell_x, n_cell_y, n_cell_z);
        }

        // Create a FieldContainer and add some fields to it
        const std::size_t n_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
        const std::size_t n_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)
        std::shared_ptr<FieldContainer> field_container = std::make_shared<FieldContainer>(grid);
        {
            // number of ghost cells
            const std::size_t n_ghost = 1; // Maybe we dont want ghost elements for some of the MultiFabs, or only in certain directions, but I just setting it the same for all of them for now.

            // number of components for each type of MultiFab

            // Create scalar and vector fields at all locations in the grid
            using FieldPtr = std::shared_ptr<Field>;
            FieldPtr cell_scalar_field   = field_container->Insert("cell_scalar",   FieldGridStagger::CellCentered, n_comp_scalar, n_ghost);
            FieldPtr cell_vector_field   = field_container->Insert("cell_vector",   FieldGridStagger::CellCentered, n_comp_vector, n_ghost);

            FieldPtr node_scalar_field   = field_container->Insert("node_scalar",   FieldGridStagger::Nodal,        n_comp_scalar, n_ghost);
            FieldPtr node_vector_field   = field_container->Insert("node_vector",   FieldGridStagger::Nodal,        n_comp_vector, n_ghost);  

            FieldPtr x_face_scalar_field = field_container->Insert("x_face_scalar", FieldGridStagger::IFace,        n_comp_scalar, n_ghost);
            FieldPtr x_face_vector_field = field_container->Insert("x_face_vector", FieldGridStagger::IFace,        n_comp_vector, n_ghost);

            FieldPtr y_face_scalar_field = field_container->Insert("y_face_scalar", FieldGridStagger::JFace,        n_comp_scalar, n_ghost);
            FieldPtr y_face_vector_field = field_container->Insert("y_face_vector", FieldGridStagger::JFace,        n_comp_vector, n_ghost);

            FieldPtr z_face_scalar_field = field_container->Insert("z_face_scalar", FieldGridStagger::KFace,        n_comp_scalar, n_ghost);
            FieldPtr z_face_vector_field = field_container->Insert("z_face_vector", FieldGridStagger::KFace,        n_comp_vector, n_ghost);
        }

        // Loop over all the fields in the FieldContainer and print out their names and FieldGridStagger
        for (const auto& field : *field_container) {
            amrex::Print() << "Field name: " << field->name << ", FieldGridStagger: " << FieldGridStaggerToString(field->field_grid_stagger) << "\n";
        }

        // Initialize scalar and vector MultiFabs with some example data
        for (const auto& field : *field_container) {
            if (field->multifab->nComp() == n_comp_scalar) {

                // Can be replaced with any other initializer function that takes (double x, double y, double z) and returns a double value.
                auto scalar_initializer_function = [](double x, double y, double z) {
                    return x; 
                };

                for (amrex::MFIter mfi(*field->multifab); mfi.isValid(); ++mfi) {
                    const amrex::Array4<amrex::Real>& array = field->multifab->array(mfi);
                    amrex::ParallelFor(mfi.validbox(), [=] AMREX_GPU_DEVICE(int i, int j, int k) {
                        const Grid::Point grid_point = field->GetGridPoint(i, j, k); 
                        array(i, j, k) = scalar_initializer_function(grid_point.x, grid_point.y, grid_point.z);
                    });
                }
            }
            else if (field->multifab->nComp() == n_comp_vector) {

                // Can be replaced with any other initializer function that takes (double x, double y, double z) and returns a std::array<double, 3>.
                auto vector_initializer_function = [](double x, double y, double z) {
                    return std::array<double, 3>{x, y, z}; // Example initializer function
                };

                for (amrex::MFIter mfi(*field->multifab); mfi.isValid(); ++mfi) {
                    const amrex::Array4<amrex::Real>& array = field->multifab->array(mfi);
                    amrex::ParallelFor(mfi.validbox(), [=] AMREX_GPU_DEVICE(int i, int j, int k) {
                        const Grid::Point grid_point = field->GetGridPoint(i, j, k);
                        std::array<double, 3> initial_vector = vector_initializer_function(grid_point.x, grid_point.y, grid_point.z);
                        array(i, j, k, 0) = initial_vector[0];
                        array(i, j, k, 1) = initial_vector[1];
                        array(i, j, k, 2) = initial_vector[2];
                    });
                }
            }
            else {
                amrex::Abort("MultiFab has an unexpected number of components.");
            }
        }
    
        WriteHDF5("initialization_mini_app.h5", field_container);

    }

    amrex::Finalize();
    return 0;
}
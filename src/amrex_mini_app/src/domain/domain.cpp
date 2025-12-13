#include <string>
#include <memory>
#include <stdexcept>
#include <ranges>

#include <hdf5.h>

#include <AMReX.H>

#include "domain.h"
#include "geometry.h"
#include "grid.h"
#include "field.h"

namespace turbo {

//Domain::Domain(const std::shared_ptr<Geometry>& geometry,
//            const std::shared_ptr<Grid>& grid)
//                : geometry_(geometry), grid_(grid), field_container_({}) {}

Domain::Domain(const std::shared_ptr<Grid>& grid)
                : grid_(grid), field_container_({}) {}

std::shared_ptr<Geometry> Domain::GetGeometry() const noexcept { return grid_->GetGeometry(); }

std::shared_ptr<Grid> Domain::GetGrid() const noexcept { return grid_; }

std::shared_ptr<Field> Domain::CreateField(const Field::NameType& name, const FieldGridStagger stagger,
                                       const std::size_t n_component, const std::size_t n_ghost)
{
    if (field_container_.contains(name))
    {
        throw std::invalid_argument("FieldContainer::Insert: Field with name '" + name + "' already exists.");
    }

    const std::shared_ptr<Field> field = std::make_shared<Field>(name, grid_, stagger, n_component, n_ghost);
    auto [iter, inserted]              = field_container_.insert({name, field});
    if (!inserted)
    {
        // Since we already checked that no value with this key exist in the map and created the field pointer,
        //  the insert should always succeed and we should never reach this point.
        throw std::logic_error(
            "FieldContainer::Insert: Failed to insert field. Somehow it was not inserted into the map used under the "
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
    // Maybe we want to do something else instead of throwing an exception here?
    throw std::invalid_argument("FieldContainer::Get: Field with name '" + name + "' does not exist.");
}

bool Domain::HasField(const Field::NameType& field_name) const 
{
    return field_container_.contains(field_name);
}

void Domain::WriteHDF5(const std::string& filename) const {

    hid_t file_id;

    // Only the IOProcessor writes the grid information and metadata
    if (amrex::ParallelDescriptor::IOProcessor()) {

        //amrex::AllPrint() << "Going to create HDF5 file: " << filename <<  " from IOProcessor " << amrex::ParallelDescriptor::IOProcessorNumber() << std::endl; 

        file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);

        if (file_id < 0) {
            throw std::runtime_error("Invalid HDF5 file_id passed to WriteHDF5.");
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

        grid_->WriteHDF5(file_id);

    }

    for (const auto& field : GetFields()) {
        field->WriteHDF5(file_id);
    }

    if (amrex::ParallelDescriptor::IOProcessor()) {
        H5Fclose(file_id);
    }

    //WriteXDMF(filename, "test.xdmf");

}

//void Domain::WriteXDMF(const std::string& h5_filename,
//                             const std::string& xdmf_filename) const {
//
//    if (amrex::ParallelDescriptor::MyProc() == 0) {
//
//        std::ofstream xdmf(xdmf_filename);
//        xdmf << "<?xml version=\"1.0\" ?>\n";
//        xdmf << "<Xdmf Version=\"3.0\">\n";
//        xdmf << "  <Domain>\n";
//
//        struct GridInfo {
//            std::string name;
//            std::vector<int> dims;
//            std::string geometry_dataset;
//            std::string scalar_dataset;
//            std::string vector_dataset;
//            std::string scalar_name;
//            std::string vector_name;
//            std::string center;
//        };
//
//        const int nx = NCellX();
//        const int ny = NCellY();
//        const int nz = NCellZ();
//
//        std::vector<GridInfo> grids = {
//            {"cell_center", {nz, ny, nx}, "cell_center", "cell_scalar", "cell_vector", "Cell Scalar", "Cell Vector", "Cell"},
//            {"node", {nz+1, ny+1, nx+1}, "node", "node_scalar", "node_vector", "Node Scalar", "Node Vector", "Node"},
//            {"x_face", {nz, ny, nx+1}, "x_face", "x_face_scalar", "x_face_vector", "X-Face Scalar", "X-Face Vector", "Face"},
//            {"y_face", {nz, ny+1, nx}, "y_face", "y_face_scalar", "y_face_vector", "Y-Face Scalar", "Y-Face Vector", "Face"},
//            {"z_face", {nz+1, ny, nx}, "z_face", "z_face_scalar", "z_face_vector", "Z-Face Scalar", "Z-Face Vector", "Face"}
//        };
//
//        auto WriteXDMFDataItem = [&xdmf, &h5_filename](const std::string& dataset,
//                                     const std::vector<int>& dims,
//                                     int n_comp) {
//            xdmf << "        <DataItem Dimensions=\"";
//            for (size_t i = 0; i < dims.size(); ++i) xdmf << dims[i] << " ";
//            if (n_comp > 1) xdmf << n_comp;
//            xdmf << "\" NumberType=\"Float\" Precision=\"8\" Format=\"HDF\">\n";
//            xdmf << "          " << h5_filename << ":/" << dataset << "\n";
//            xdmf << "        </DataItem>\n";
//        };
//
//        for (const auto& grid : grids) {
//            xdmf << "    <Grid Name=\"" << grid.name << "\" GridType=\"Uniform\">\n";
//
//            xdmf << "      <Topology TopologyType=\"3DRectMesh\" Dimensions=\"";
//            for (size_t i = 0; i < grid.dims.size(); ++i) xdmf << grid.dims[i] << " ";
//            xdmf << "\"/>\n";
//
//            xdmf << "      <Geometry GeometryType=\"XYZ\">\n";
//            WriteXDMFDataItem(grid.geometry_dataset, grid.dims, 3);
//            xdmf << "      </Geometry>\n";
//
//            // Scalar field
//            xdmf << "      <Attribute Name=\"" << grid.scalar_name << "\" AttributeType=\"Scalar\" Center=\"" << grid.center << "\">\n";
//            WriteXDMFDataItem(grid.scalar_dataset, grid.dims, 1);
//            xdmf << "      </Attribute>\n";
//
//            // Vector field
//            xdmf << "      <Attribute Name=\"" << grid.vector_name << "\" AttributeType=\"Vector\" Center=\"" << grid.center << "\">\n";
//            WriteXDMFDataItem(grid.vector_dataset, grid.dims, 3);
//            xdmf << "      </Attribute>\n";
//
//            xdmf << "    </Grid>\n";
//        }
//
//        xdmf << "  </Domain>\n";
//        xdmf << "</Xdmf>\n";
//        xdmf.close();
//    }
//}


} // namespace turbo
#include <cstddef> // for std::size_t
#include <string>
#include <fstream>

#include <hdf5.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "tripolar_grid.h"

// Point operator+
TripolarGrid::Point TripolarGrid::Point::operator+(const Point& other) const noexcept {
    return {x + other.x, y + other.y, z + other.z};
}

TripolarGrid::TripolarGrid(std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z)
    : n_cell_x_(n_cell_x), n_cell_y_(n_cell_y), n_cell_z_(n_cell_z)
{
    static_assert(
        amrex::SpaceDim == 3,
        "Only supports 3D grids."
    );

    // Initialize the MultiFabs

    // number of ghost cells
    const int n_ghost = 1; // Maybe we dont want ghost elements for some of the MultiFabs, or only in certain directions, but I just setting it the same for all of them for now.

    // number of components for each MultiFab
    const int n_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
    const int n_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)

    // Create MultiFabs for scalar and vector fields on the cell-centered grid
    {
        // We don't really need the AMREX_D_DECL here since we are enforcing 3D grids only, but it's fine to keep it for now to avoid potential issues if we decide to extend to 2D or 1D later.
        // If or when we do that we will need to wrap all the change the other IntVect definitions accordingly.
        const amrex::IntVect cell_low_index(AMREX_D_DECL(0,0,0));
        const amrex::IntVect cell_high_index(AMREX_D_DECL(n_cell_x - 1, n_cell_y - 1, n_cell_z - 1));
        const amrex::Box cell_centered_box(cell_low_index, cell_high_index);

        amrex::BoxArray cell_box_array(cell_centered_box);
        // Break up boxarray "cell_box_array" into chunks no larger than "max_chunk_size" along a direction
        const int max_chunk_size = 32; // Hardcoded for now, but could be a parameter for the user to set via the constructor arguments.
        cell_box_array.maxSize(max_chunk_size);

        const amrex::DistributionMapping distribution_mapping(cell_box_array);

        cell_scalar = std::make_shared<amrex::MultiFab>(cell_box_array, distribution_mapping, n_comp_scalar, n_ghost);
        cell_vector = std::make_shared<amrex::MultiFab>(cell_box_array, distribution_mapping, n_comp_vector, n_ghost);
    }

    // Defining the MultiFab on the nodes and faces assume these two are defined on cells. Confirm that.
    AMREX_ASSERT(cell_scalar.is_cell_centered());
    AMREX_ASSERT(cell_scalar->is_cell_centered());
    AMREX_ASSERT(cell_vector->is_cell_centered());

    // All subsequent MultiFabs will be defined based on the cell-centered MultiFab distribution mapping. 
    const amrex::DistributionMapping distribution_mapping = cell_scalar->DistributionMap();

    // All subsequent MultiFabs box arrays will be adjusted accordingly using convert and the box array from the cell-centered MultiFabs.
    const amrex::BoxArray& cell_box_array = cell_scalar->boxArray();

    // Create MultiFabs for scalar and vector fields on the x-face-centered grid
    {
        // Convert the cell-centered box array to x-face-centered
        const amrex::BoxArray x_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(1,0,0));

        // Define the MultiFab for x-face-centered scalar field
        x_face_scalar = std::make_shared<amrex::MultiFab>(x_face_box_array, distribution_mapping, n_comp_scalar, n_ghost);
        x_face_vector = std::make_shared<amrex::MultiFab>(x_face_box_array, distribution_mapping, n_comp_vector, n_ghost);
    }

    // Create MultiFabs for scalar and vector fields on the y-face-centered grid
    {
        // Convert the cell-centered box array to y-face-centered
        const amrex::BoxArray y_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(0,1,0));

        y_face_scalar = std::make_shared<amrex::MultiFab>(y_face_box_array, distribution_mapping, n_comp_scalar, n_ghost);
        y_face_vector = std::make_shared<amrex::MultiFab>(y_face_box_array, distribution_mapping, n_comp_vector, n_ghost);

    }

    // Create MultiFabs for scalar and vector fields on the z-face-centered grid
    {
        // Convert the cell-centered box array to z-face-centered
        const amrex::BoxArray z_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(0,0,1));

        z_face_scalar = std::make_shared<amrex::MultiFab>(z_face_box_array, distribution_mapping, n_comp_scalar, n_ghost);
        z_face_vector = std::make_shared<amrex::MultiFab>(z_face_box_array, distribution_mapping, n_comp_vector, n_ghost);

    }

    // Create MultiFabs for scalar and vector fields on the nodal grid
    {
        // Convert the cell-centered box array to nodal
        const amrex::BoxArray nodal_box_array = amrex::convert(cell_box_array, amrex::IntVect(1,1,1));

        node_scalar = std::make_shared<amrex::MultiFab>(nodal_box_array, distribution_mapping, n_comp_scalar, n_ghost);
        node_vector = std::make_shared<amrex::MultiFab>(nodal_box_array, distribution_mapping, n_comp_vector, n_ghost);
    }

    // Collections of MultiFabs for easier looping and testing
    all_multifabs = {
        cell_scalar,
        cell_vector,
        x_face_scalar,
        x_face_vector,
        y_face_scalar,
        y_face_vector,
        z_face_scalar,
        z_face_vector,
        node_scalar,
        node_vector
    };

    for (const std::shared_ptr<amrex::MultiFab>& mf : all_multifabs) {

        if (mf->nComp() == n_comp_scalar) {
            scalar_multifabs.insert(mf);
        } else if (mf->nComp() == n_comp_vector) {
            vector_multifabs.insert(mf);
        } else {
            amrex::Abort("MultiFab has an unexpected number of components.");
        }

        if (mf->is_cell_centered()) {
            cell_multifabs.insert(mf);
        } else if (mf->is_nodal(0) == true  && mf->is_nodal(1) == false && mf->is_nodal(2) == false) {
            x_face_multifabs.insert(mf);
        } else if (mf->is_nodal(0) == false && mf->is_nodal(1) == true  && mf->is_nodal(2) == false) {
            y_face_multifabs.insert(mf);
        } else if (mf->is_nodal(0) == false && mf->is_nodal(1) == false && mf->is_nodal(2) == true) {
            z_face_multifabs.insert(mf);
        } else if (mf->is_nodal()) {
            node_multifabs.insert(mf);
        } else {
            amrex::Abort("MultiFab has an unexpected topology.");
        }

    }


}

std::size_t TripolarGrid::NCell() const noexcept  { return n_cell_x_ * n_cell_y_ * n_cell_z_; }
std::size_t TripolarGrid::NCellX() const noexcept { return n_cell_x_; }
std::size_t TripolarGrid::NCellY() const noexcept { return n_cell_y_; }
std::size_t TripolarGrid::NCellZ() const noexcept { return n_cell_z_; }

std::size_t TripolarGrid::NNode() const noexcept  { return NNodeX() * NNodeY() * NNodeZ(); }
std::size_t TripolarGrid::NNodeX() const noexcept { return NCellX() + 1; }
std::size_t TripolarGrid::NNodeY() const noexcept { return NCellY() + 1; }
std::size_t TripolarGrid::NNodeZ() const noexcept { return NCellZ() + 1; }

TripolarGrid::Point TripolarGrid::Node(amrex::IntVect node_index) const noexcept {
    return {x_min_ + node_index[0] * dx_,
            y_min_ + node_index[1] * dy_,
            z_min_ + node_index[2] * dz_};
}

TripolarGrid::Point TripolarGrid::CellCenter(amrex::IntVect cell_index) const noexcept {
    return Node(cell_index) + Point{dx_*0.5, dy_*0.5, dz_*0.5};
}

TripolarGrid::Point TripolarGrid::XFace(amrex::IntVect x_face_index) const noexcept {
    return Node(x_face_index) + Point{0.0, dy_*0.5, dz_*0.5};
}

TripolarGrid::Point TripolarGrid::YFace(amrex::IntVect y_face_index) const noexcept {
    return Node(y_face_index) + Point{dx_*0.5, 0.0, dz_*0.5};
}

TripolarGrid::Point TripolarGrid::ZFace(amrex::IntVect z_face_index) const noexcept {
    return Node(z_face_index) + Point{dx_*0.5, dy_*0.5, 0.0};
}

TripolarGrid::Point TripolarGrid::GetLocation(const std::shared_ptr<amrex::MultiFab>& mf, int i, int j, int k) const {
    if (cell_multifabs.contains(mf)) {
        return CellCenter(amrex::IntVect(i,j,k));
    } else if (x_face_multifabs.contains(mf)) {
        return XFace(amrex::IntVect(i,j,k));
    } else if (y_face_multifabs.contains(mf)) {
        return YFace(amrex::IntVect(i,j,k));
    } else if (z_face_multifabs.contains(mf)) {
        return ZFace(amrex::IntVect(i,j,k));
    } else if (node_multifabs.contains(mf)) {
        return Node(amrex::IntVect(i,j,k));
    } else {
        amrex::Abort("MultiFab was not found in any of the location sets.");
        return {}; // Returned this line to silence the warning about control reaching end of non-void function. Will never be reached because we are calling abort in this case.
    }
}

void TripolarGrid::WriteHDF5(const std::string& filename) const {

    const hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);

    // Write the attributes from rank 0
    if (amrex::ParallelDescriptor::MyProc() == 0) {


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

    }

    WriteGeometryToHDF5(file_id);

    WriteMultiFabsToHDF5(file_id);

    H5Fclose(file_id);

    //WriteXDMF(filename, "test.xdmf");

}

std::shared_ptr<amrex::MultiFab> TripolarGrid::CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& source_mf, int dest_rank) const {

    // Create a temporary MultiFab to hold all the data on a single ran
    const amrex::BoxArray box_array_with_one_box(source_mf->boxArray().minimalBox()); // BoxArray with a single box that covers the entire domain
    const amrex::DistributionMapping distribution_mapping(amrex::Vector<int>{dest_rank}); // Distribution mapping that puts the single box in the box array to a single rank
    const int n_comp = source_mf->nComp();
    const amrex::IntVect n_ghost = source_mf->nGrowVect();
    std::shared_ptr<amrex::MultiFab> dest_mf = std::make_shared<amrex::MultiFab>(box_array_with_one_box, distribution_mapping, n_comp, n_ghost);

    // Copy the data from the source MultiFab to the destination MultiFab
    const int comp_src_start = 0;
    const int comp_dest_start = 0;
    const int n_comp_copy = n_comp;
    const amrex::IntVect src_n_ghost = n_ghost;
    const amrex::IntVect dest_n_ghost = n_ghost;
    dest_mf->ParallelCopy(*source_mf, comp_src_start, comp_dest_start, n_comp_copy, src_n_ghost, dest_n_ghost);

    return dest_mf;
}


void TripolarGrid::WriteMultiFabsToHDF5(const hid_t file_id) const {

    const std::map<std::string, std::shared_ptr<amrex::MultiFab>> name_to_multifab = {
        {"cell_scalar", cell_scalar},
        {"cell_vector", cell_vector},
        {"x_face_scalar", x_face_scalar},
        {"x_face_vector", x_face_vector},
        {"y_face_scalar", y_face_scalar},
        {"y_face_vector", y_face_vector},
        {"z_face_scalar", z_face_scalar},
        {"z_face_vector", z_face_vector},
        {"node_scalar", node_scalar},
        {"node_vector", node_vector}
    };

    for (const auto& [name, src_mf] : name_to_multifab) {

        // Copy the MultiFab to a single rank
        int dest_rank = 0; // We are copying to rank 0
        const std::shared_ptr<amrex::MultiFab> mf = CopyMultiFabToSingleRank(src_mf, dest_rank);

        if (amrex::ParallelDescriptor::MyProc() == dest_rank) {

            AMREX_ASSERT(mf->boxArray().size() == 1);
            amrex::Box box = mf->boxArray()[0]; // We are assuming that there is only one box in the MultiFabs box array.

            AMREX_ASSERT(mf->size() == 1);
            const amrex::Array4<const amrex::Real>& array = mf->const_array(0); // Assuming there is only one FAB in the MultiFab

            const int nx = box.length(0); 
            const int ny = box.length(1); 
            const int nz = box.length(2);
            const int n_component = mf->nComp();
            std::vector<hsize_t> dims = {static_cast<hsize_t>(nx), static_cast<hsize_t>(ny), static_cast<hsize_t>(nz)}; 
            if (n_component > 1) {
                dims.push_back(static_cast<hsize_t>(n_component));
            }

            const hid_t dataspace_id = H5Screate_simple(dims.size(), dims.data(), NULL);
            const hid_t dataset_id = H5Dcreate(file_id, name.c_str(), H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);

            std::vector<double> data(nx * ny * nz * n_component); 

            // Iterate over the components of the MultiFab and fill the data vector... putting in row-major order instead of column-major order
            const auto lo = amrex::lbound(box);
            const auto hi = amrex::ubound(box);
            std::size_t idx = 0;
            for (int i = lo.x; i <= hi.x; ++i) {
                for (int j = lo.y; j <= hi.y; ++j) {
                    for (int k = lo.z; k <= hi.z; ++k) {
                        for (int component_idx = 0; component_idx < n_component; ++component_idx) {
                            data[idx++] = array(i, j, k, component_idx);
                        }
                    }
                }
            }          

            H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data.data());

            H5Dclose(dataset_id);
            H5Sclose(dataspace_id);

        }
    }
}

void TripolarGrid::WriteGeometryToHDF5(const hid_t file_id) const {

    const std::map<std::string, std::shared_ptr<amrex::MultiFab>> geometry_name_to_a_multifab_at_that_location = {
        {"cell_center", cell_scalar},
        {"x_face", x_face_scalar},
        {"y_face", y_face_scalar},
        {"z_face", z_face_scalar},
        {"node", node_scalar},
    };

    for (const auto& [name, mf] : geometry_name_to_a_multifab_at_that_location) {
    
        if (amrex::ParallelDescriptor::MyProc() == 0) {
    
            const amrex::Box box = mf->boxArray().minimalBox(); 
    
            const int nx = box.length(0); 
            const int ny = box.length(1); 
            const int nz = box.length(2);
            const int n_component = 3;
            std::vector<hsize_t> dims = {static_cast<hsize_t>(nx), static_cast<hsize_t>(ny), static_cast<hsize_t>(nz), static_cast<hsize_t>(n_component)}; 
    
            const hid_t dataspace_id = H5Screate_simple(dims.size(), dims.data(), NULL);
            const hid_t dataset_id = H5Dcreate(file_id, name.c_str(), H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    
            std::vector<double> data(nx * ny * nz * n_component); 
    
            // Iterate over the components of the MultiFab and fill the data vector... putting in row-major order instead of column-major order
            const auto lo = amrex::lbound(box);
            const auto hi = amrex::ubound(box);
            std::size_t idx = 0;
            for (int i = lo.x; i <= hi.x; ++i) {
                for (int j = lo.y; j <= hi.y; ++j) {
                    for (int k = lo.z; k <= hi.z; ++k) {

                        const Point location = GetLocation(mf, i, j, k);
                        data[idx++] = location.x;
                        data[idx++] = location.y;
                        data[idx++] = location.z;

                    }
                }
            }          
    
            H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data.data());
    
            H5Dclose(dataset_id);
            H5Sclose(dataspace_id);
    
        }
    }

}

//void TripolarGrid::WriteXDMF(const std::string& h5_filename,
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
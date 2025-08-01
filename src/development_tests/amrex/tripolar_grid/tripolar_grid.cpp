#include <cstddef> // for std::size_t
#include <string>

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
    const int N_ghost = 1; // Maybe we dont want ghost elements for some of the MultiFabs, or only in certain directions, but I just setting it the same for all of them for now.

    // number of components for each MultiFab
    const int N_comp_scalar = 1; // Scalar field, e.g., temperature or pressure
    const int N_comp_vector = 3; // Vector field, e.g., velocity (u, v, w)

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

        cell_scalar = std::make_shared<amrex::MultiFab>(cell_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        cell_vector = std::make_shared<amrex::MultiFab>(cell_box_array, distribution_mapping, N_comp_vector, N_ghost);
    }

    // Defining the MultiFab on the nodes and faces assume these two are defined on cells. Confirm that.
    AMREX_ASSERT(cell_scalar.is_cell_centered());
    AMREX_ASSERT(cell_vector.is_cell_centered());

    // All subsequent MultiFabs will be defined based on the cell-centered MultiFab distribution mapping. 
    const amrex::DistributionMapping distribution_mapping = cell_scalar->DistributionMap();

    // All subsequent MultiFabs box arrays will be adjusted accordingly using convert and the box array from the cell-centered MultiFabs.
    const amrex::BoxArray& cell_box_array = cell_scalar->boxArray();

    // Create MultiFabs for scalar and vector fields on the x-face-centered grid
    {
        // Convert the cell-centered box array to x-face-centered
        const amrex::BoxArray x_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(1,0,0));

        // Define the MultiFab for x-face-centered scalar field
        x_face_scalar = std::make_shared<amrex::MultiFab>(x_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        x_face_vector = std::make_shared<amrex::MultiFab>(x_face_box_array, distribution_mapping, N_comp_vector, N_ghost);
    }

    // Create MultiFabs for scalar and vector fields on the y-face-centered grid
    {
        // Convert the cell-centered box array to y-face-centered
        const amrex::BoxArray y_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(0,1,0));

        y_face_scalar = std::make_shared<amrex::MultiFab>(y_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        y_face_vector = std::make_shared<amrex::MultiFab>(y_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

    }

    // Create MultiFabs for scalar and vector fields on the z-face-centered grid
    {
        // Convert the cell-centered box array to z-face-centered
        const amrex::BoxArray z_face_box_array = amrex::convert(cell_box_array, amrex::IntVect(0,0,1));

        z_face_scalar = std::make_shared<amrex::MultiFab>(z_face_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        z_face_vector = std::make_shared<amrex::MultiFab>(z_face_box_array, distribution_mapping, N_comp_vector, N_ghost);

    }

    // Create MultiFabs for scalar and vector fields on the nodal grid
    {
        // Convert the cell-centered box array to nodal
        const amrex::BoxArray nodal_box_array = amrex::convert(cell_box_array, amrex::IntVect(1,1,1));

        node_scalar = std::make_shared<amrex::MultiFab>(nodal_box_array, distribution_mapping, N_comp_scalar, N_ghost);
        node_vector = std::make_shared<amrex::MultiFab>(nodal_box_array, distribution_mapping, N_comp_vector, N_ghost);
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

        if (mf->nComp() == N_comp_scalar) {
            scalar_multifabs.insert(mf);
        } else if (mf->nComp() == N_comp_vector) {
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

    //for (const std::shared_ptr<amrex::MultiFab>& mf : scalar_multifabs) {
    for (const std::shared_ptr<amrex::MultiFab>& src_mf : {cell_scalar}) {

        // Copy the MultiFab to a single rank
        int dest_rank = 0; // We are copying to rank 0
        const std::shared_ptr<amrex::MultiFab> mf = CopyMultiFabToSingleRank(src_mf, dest_rank);

        if (amrex::ParallelDescriptor::MyProc() == dest_rank) {

            AMREX_ASSERT(mf->boxArray().size() == 1);
            amrex::Box bx = mf->boxArray()[0]; // We are assuming that there is only one box in the MultiFabs box array.

            AMREX_ASSERT(mf->size() == 1);
            const amrex::Array4<const amrex::Real>& array = mf->const_array(0); // Assuming there is only one FAB in the MultiFab

            {
              double test_value = 0.0; // Example test value, can be set to any value you want
              const hid_t attr_space_id = H5Screate(H5S_SCALAR);
              const hid_t attr_id = H5Acreate(file_id, "test_value", H5T_NATIVE_DOUBLE, attr_space_id, H5P_DEFAULT, H5P_DEFAULT);
              H5Awrite(attr_id, H5T_NATIVE_DOUBLE, &test_value);
              H5Aclose(attr_id);
              H5Sclose(attr_space_id);
            }

            const auto lo = lbound(bx);
            const auto hi = ubound(bx);
            for (int n = 0; n < mf->nComp(); ++n) {
              for     (int k = lo.z; k <= hi.z; ++k) {
                for   (int j = lo.y; j <= hi.y; ++j) {
                  for (int i = lo.x; i <= hi.x; ++i) {
                    //amrex::AllPrint() << "array(" << i << "," << j << "," << k << ") = " << array(i,j,k) << "\n";
                    amrex::AllPrint() << "array(" << i << "," << j << "," << k << "," << n << ") = " << array(i,j,k,n) << "\n";
                  }
                }
              }
            }          

        }
    }

    H5Fclose(file_id);

}

std::shared_ptr<amrex::MultiFab> TripolarGrid::CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& source_mf, int dest_rank) const {

    // Create a temporary MultiFab to hold all the data on a single rank
    const amrex::BoxArray box_array_with_one_box(source_mf->boxArray().minimalBox()); // BoxArray with a single box that covers the entire domain
    const amrex::DistributionMapping distribution_mapping(amrex::Vector<int>{dest_rank}); // Distribution mapping that puts the single box in the box array to a single rank
    const int n_comp = source_mf->nComp();
    //const int n_ghost = source_mf->nGrow();
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
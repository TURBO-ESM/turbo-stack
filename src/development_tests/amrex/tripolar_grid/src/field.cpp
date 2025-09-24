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

std::shared_ptr<amrex::MultiFab> FieldContainer::AddField(const std::string& name, const FieldLocation field_location, std::size_t n_component, std::size_t n_ghost) {
    if (name_to_multifab.find(name) != name_to_multifab.end()) {
        throw std::invalid_argument("FieldContainer::AddField: Field with name '" + name + "' already exists.");
    }

    if (n_component <= 0) {
        throw std::invalid_argument("FieldContainer::AddField: Number of components must be greater than zero.");
    }

    if (n_ghost < 0) {
        throw std::invalid_argument("FieldContainer::AddField: Number of ghost cells cannot be negative.");
    }

    const amrex::IntVect lower_index(AMREX_D_DECL(0,0,0));

    amrex::IntVect upper_index;
    switch (field_location) {
        case FieldLocation::CellCentered:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid_->NCellI() - 1, grid_->NCellJ() - 1, grid_->NCellK() - 1));
            break;
        case FieldLocation::IFace:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid_->NNodeI() - 1, grid_->NCellJ() - 1, grid_->NCellK() - 1));
            break;
        case FieldLocation::JFace:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid_->NCellI() - 1, grid_->NNodeJ() - 1, grid_->NCellK() - 1));
            break;
        case FieldLocation::KFace:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid_->NCellI() - 1, grid_->NCellJ() - 1, grid_->NNodeK() - 1));
            break;
        case FieldLocation::Nodal:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid_->NNodeI() - 1, grid_->NNodeJ() - 1, grid_->NNodeK() - 1));
            break;
        default:
            throw std::invalid_argument("FieldContainer::AddField: Invalid FieldLocation specified.");
    }

    const amrex::IndexType index_type(FieldLocationToAMReXIndexType(field_location));

    const amrex::Box box(lower_index, upper_index, index_type);

    amrex::BoxArray box_array(box);

    // Break up boxarray "cell_box_array" into chunks no larger than "max_chunk_size" along a direction
    const int max_chunk_size = 32; // Hardcoded for now, but could be a parameter for the user to set via the constructor arguments.
    box_array.maxSize(max_chunk_size);

    const amrex::DistributionMapping distribution_mapping(box_array);

    auto mf = std::make_shared<amrex::MultiFab>(box_array, distribution_mapping, n_component, n_ghost);
    name_to_multifab[name] = mf;

    return mf;

}

void FieldContainer::WriteHDF5(const hid_t file_id) const {

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


} // namespace turbo
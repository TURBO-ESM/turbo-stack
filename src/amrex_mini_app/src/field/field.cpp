#include "field.h"

#include <AMReX.H>
#include <AMReX_MultiFab.H>
#include <hdf5.h>

#include <cstddef>
#include <memory>
#include <ostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "grid.h"

namespace turbo
{

Field::Field(const Field::NameType& name, const std::shared_ptr<Grid>& grid, const FieldGridStagger field_grid_stagger,
             const std::size_t n_component, const std::size_t n_ghost)
    : name(name), grid(grid), field_grid_stagger(field_grid_stagger)
{
    // Check that grid is a valid pointer.
    if (!grid)
    {
        throw std::invalid_argument("Field::Field: Invalid grid pointer.");
    }

    if (n_component == 0)
    {
        throw std::invalid_argument("Field::Field: Number of components must be greater than zero.");
    }

    const amrex::IntVect lower_index(AMREX_D_DECL(0, 0, 0));

    amrex::IntVect upper_index;
    switch (field_grid_stagger)
    {
        case FieldGridStagger::CellCentered:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid->NCellI() - 1, grid->NCellJ() - 1, grid->NCellK() - 1));
            break;
        case FieldGridStagger::IFace:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid->NNodeI() - 1, grid->NCellJ() - 1, grid->NCellK() - 1));
            break;
        case FieldGridStagger::JFace:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid->NCellI() - 1, grid->NNodeJ() - 1, grid->NCellK() - 1));
            break;
        case FieldGridStagger::KFace:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid->NCellI() - 1, grid->NCellJ() - 1, grid->NNodeK() - 1));
            break;
        case FieldGridStagger::Nodal:
            upper_index = amrex::IntVect(AMREX_D_DECL(grid->NNodeI() - 1, grid->NNodeJ() - 1, grid->NNodeK() - 1));
            break;
        default:
            throw std::invalid_argument("Field::Field: Invalid FieldGridStagger specified.");
    }

    const amrex::IndexType index_type(FieldGridStaggerToAMReXIndexType(field_grid_stagger));

    const amrex::Box box(lower_index, upper_index, index_type);

    amrex::BoxArray box_array(box);

    // Break up boxarray "cell_box_array" into chunks no larger than "max_chunk_size" along a direction
    // Hardcoded for now, but could be a parameter for the user to set via the constructor arguments.
    const int max_chunk_size = 32;
    box_array.maxSize(max_chunk_size);

    const amrex::DistributionMapping distribution_mapping(box_array);

    multifab = std::make_shared<amrex::MultiFab>(box_array, distribution_mapping, n_component, n_ghost);
}

std::ostream& operator<<(std::ostream& os, const Field& field)
{
    os << "Field Name: " << field.name << std::endl;
    os << "Field Grid Stagger: " << FieldGridStaggerToString(field.field_grid_stagger) << std::endl;
    os << "Number of Components: " << field.multifab->nComp() << std::endl;
    os << "Number of Ghost Cells: " << field.multifab->nGrow() << std::endl;
    return os;
}

bool Field::IsCellCentered() const noexcept { return (field_grid_stagger == FieldGridStagger::CellCentered); }

bool Field::IsIFaceCentered() const noexcept { return (field_grid_stagger == FieldGridStagger::IFace); }

bool Field::IsJFaceCentered() const noexcept { return (field_grid_stagger == FieldGridStagger::JFace); }

bool Field::IsKFaceCentered() const noexcept { return (field_grid_stagger == FieldGridStagger::KFace); }

bool Field::IsNodal() const noexcept { return (field_grid_stagger == FieldGridStagger::Nodal); }

// This is where the coupling between the Field and Grid classes happens
Grid::Point Field::GetGridPoint(int i, int j, int k) const
{
    switch (field_grid_stagger)
    {
        case FieldGridStagger::CellCentered:
            return grid->CellCenter(i, j, k);
        case FieldGridStagger::IFace:
            return grid->IFace(i, j, k);
        case FieldGridStagger::JFace:
            return grid->JFace(i, j, k);
        case FieldGridStagger::KFace:
            return grid->KFace(i, j, k);
        case FieldGridStagger::Nodal:
            return grid->Node(i, j, k);
        default:
            throw std::invalid_argument("Field::GetGridPoint: Invalid FieldGridStagger specified.");
    }
}

// Write the field data to an HDF5 file. This will overwrite the file if it already exists.
void Field::WriteHDF5(const std::string& filename) const
{
    hid_t file_id;
    if (amrex::ParallelDescriptor::IOProcessor())
    {
        file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
        if (file_id < 0)
        {
            throw std::runtime_error("Field::WriteHDF5: Failed to create HDF5 file: " + filename);
        }
    }

    WriteHDF5(file_id);

    if (amrex::ParallelDescriptor::IOProcessor())
    {
        H5Fclose(file_id);
    }
}

// Write the field data to an already open HDF5 file that you already have open.
void Field::WriteHDF5(const hid_t file_id) const
{
    // Copy the MultiFab to a single rank
    int destination_rank                      = amrex::ParallelDescriptor::IOProcessorNumber();
    const std::shared_ptr<amrex::MultiFab> mf = CopyMultiFabToSingleRank(multifab, destination_rank);

    if (amrex::ParallelDescriptor::MyProc() == destination_rank)
    {
        if (file_id < 0)
        {
            throw std::runtime_error("Field::WriteHDF5: Invalid HDF5 file_id passed to WriteHDF5.");
        }

        AMREX_ASSERT(mf->boxArray().size() == 1);
        amrex::Box box = mf->boxArray()[0];  // We are assuming that there is only one box in the MultiFabs box array.

        AMREX_ASSERT(mf->size() == 1);
        const amrex::Array4<const amrex::Real>& array =
            mf->const_array(0);  // Assuming there is only one FAB in the MultiFab

        const int nx              = box.length(0);
        const int ny              = box.length(1);
        const int nz              = box.length(2);
        const int n_component     = mf->nComp();
        std::vector<hsize_t> dims = {static_cast<hsize_t>(nx), static_cast<hsize_t>(ny), static_cast<hsize_t>(nz)};
        if (n_component > 1)
        {
            dims.push_back(static_cast<hsize_t>(n_component));
        }

        const hid_t dataspace_id = H5Screate_simple(dims.size(), dims.data(), NULL);
        const hid_t dataset_id =
            H5Dcreate(file_id, name.c_str(), H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);

        std::vector<double> data(nx * ny * nz * n_component);

        // Iterate over the components of the MultiFab and fill the data vector... putting in row-major order instead of
        // column-major order
        const auto lo   = amrex::lbound(box);
        const auto hi   = amrex::ubound(box);
        std::size_t idx = 0;
        for (int i = lo.x; i <= hi.x; ++i)
        {
            for (int j = lo.y; j <= hi.y; ++j)
            {
                for (int k = lo.z; k <= hi.z; ++k)
                {
                    for (int component_idx = 0; component_idx < n_component; ++component_idx)
                    {
                        data[idx++] = array(i, j, k, component_idx);
                    }
                }
            }
        }

        {
            // Add an attribute to specify the data layout of the following datasets (row-major or column-major)
            std::string data_layout_str = "row_major";
            hid_t attr_type             = H5Tcopy(H5T_C_S1);
            H5Tset_size(attr_type, data_layout_str.size() + 1);
            hid_t attr_space = H5Screate(H5S_SCALAR);
            hid_t attr_id    = H5Acreate2(dataset_id, "data_layout", attr_type, attr_space, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, attr_type, data_layout_str.c_str());
            H5Aclose(attr_id);
            H5Sclose(attr_space);
            H5Tclose(attr_type);
        }

        {
            // Add string attribute to this dataset for field_grid_stagger
            std::string stagger_str = FieldGridStaggerToString(field_grid_stagger);
            hid_t attr_type         = H5Tcopy(H5T_C_S1);
            H5Tset_size(attr_type, stagger_str.size() + 1);
            hid_t attr_space = H5Screate(H5S_SCALAR);
            hid_t attr_id =
                H5Acreate2(dataset_id, "field_grid_stagger", attr_type, attr_space, H5P_DEFAULT, H5P_DEFAULT);
            H5Awrite(attr_id, attr_type, stagger_str.c_str());
            H5Aclose(attr_id);
            H5Sclose(attr_space);
            H5Tclose(attr_type);
        }

        H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data.data());

        H5Dclose(dataset_id);
        H5Sclose(dataspace_id);
    }
}

amrex::IndexType Field::FieldGridStaggerToAMReXIndexType(const FieldGridStagger field_location) const
{
    switch (field_location)
    {
        case FieldGridStagger::Nodal:
            return amrex::IndexType({AMREX_D_DECL(1, 1, 1)});
        case FieldGridStagger::CellCentered:
            return amrex::IndexType({AMREX_D_DECL(0, 0, 0)});
        case FieldGridStagger::IFace:
            return amrex::IndexType({AMREX_D_DECL(1, 0, 0)});
        case FieldGridStagger::JFace:
            return amrex::IndexType({AMREX_D_DECL(0, 1, 0)});
        case FieldGridStagger::KFace:
            return amrex::IndexType({AMREX_D_DECL(0, 0, 1)});
        default:
            throw std::invalid_argument("Field::FieldGridStaggerToAMReXIndexType: Invalid FieldGridStagger specified.");
    }
}

std::shared_ptr<amrex::MultiFab> Field::CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& source_mf,
                                                                 int destination_rank) const
{
    // Create a temporary MultiFab to hold all the data on a single rank
    const amrex::BoxArray box_array_with_one_box(
        source_mf->boxArray().minimalBox());  // BoxArray with a single box that covers the entire domain
    const amrex::DistributionMapping distribution_mapping(amrex::Vector<int>{
        destination_rank});  // Distribution mapping that puts the single box in the box array to a single rank
    const int n_comp             = source_mf->nComp();
    const amrex::IntVect n_ghost = source_mf->nGrowVect();
    std::shared_ptr<amrex::MultiFab> dest_mf =
        std::make_shared<amrex::MultiFab>(box_array_with_one_box, distribution_mapping, n_comp, n_ghost);

    // Copy the data from the source MultiFab to the destination MultiFab
    const int comp_src_start          = 0;
    const int comp_dest_start         = 0;
    const int n_comp_copy             = n_comp;
    const amrex::IntVect src_n_ghost  = n_ghost;
    const amrex::IntVect dest_n_ghost = n_ghost;
    dest_mf->ParallelCopy(*source_mf, comp_src_start, comp_dest_start, n_comp_copy, src_n_ghost, dest_n_ghost);

    return dest_mf;
}

}  // namespace turbo

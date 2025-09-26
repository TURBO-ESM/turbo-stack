#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <set>
//#include <functional>
//#include <type_traits>
//#include <unordered_set>

#include <hdf5.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "grid.h"

namespace turbo {

// Enum to specify the location of the field on the grid
enum class FieldGridStagger {
    Nodal,         
    CellCentered,  
    IFace,         
    JFace,         
    KFace          
};

// Helper function to convert FieldGridStagger to string. Convenient for error messages and generating field names on the fly.
inline std::string FieldGridStaggerToString(FieldGridStagger field_grid_stagger) {
    switch (field_grid_stagger) {
        case FieldGridStagger::Nodal:        return "Nodal";
        case FieldGridStagger::CellCentered: return "CellCentered";
        case FieldGridStagger::IFace:        return "IFace";
        case FieldGridStagger::JFace:        return "JFace";
        case FieldGridStagger::KFace:        return "KFace";
        default: throw std::invalid_argument("FieldGridStaggerToString Invalid FieldGridStagger specified.");
    }
}

class Field {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using ValueType = amrex::Real;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    Field(const std::string& name, const std::shared_ptr<Grid> grid, const FieldGridStagger field_grid_stagger, const std::size_t n_component, const std::size_t n_ghost)
        : name(name), grid(grid), field_grid_stagger(field_grid_stagger) {

        if (n_component <= 0) {
            throw std::invalid_argument("Field constructor: Number of components must be greater than zero.");
        }

        if (n_ghost < 0) {
            throw std::invalid_argument("Field constructor: Number of ghost cells cannot be negative.");
        }

        const amrex::IntVect lower_index(AMREX_D_DECL(0,0,0));

        amrex::IntVect upper_index;
        switch (field_grid_stagger) {
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
                throw std::invalid_argument("Field: Invalid FieldGridStagger specified.");
        }

        const amrex::IndexType index_type(FieldGridStaggerToAMReXIndexType(field_grid_stagger));

        const amrex::Box box(lower_index, upper_index, index_type);

        amrex::BoxArray box_array(box);

        // Break up boxarray "cell_box_array" into chunks no larger than "max_chunk_size" along a direction
        const int max_chunk_size = 32; // Hardcoded for now, but could be a parameter for the user to set via the constructor arguments.
        box_array.maxSize(max_chunk_size);

        const amrex::DistributionMapping distribution_mapping(box_array);

        multifab = std::make_shared<amrex::MultiFab>(box_array, distribution_mapping, n_component, n_ghost);

    }

    bool IsCellCentered() const noexcept{
        return (field_grid_stagger == FieldGridStagger::CellCentered);
    }

    bool IsXFaceCentered() const noexcept {
        return (field_grid_stagger == FieldGridStagger::IFace);
    }

    bool IsYFaceCentered() const noexcept{
        return (field_grid_stagger == FieldGridStagger::JFace);
    }

    bool IsZFaceCentered() const noexcept {
        return (field_grid_stagger == FieldGridStagger::KFace);
    }

    bool IsNodal() const noexcept {
        return (field_grid_stagger == FieldGridStagger::Nodal);
    }

    // This is where the coupling between the Field and Grid classes happens
    Grid::Point GetGridPoint(int i, int j, int k) const {
        switch(field_grid_stagger) {
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
                throw std::invalid_argument("Field:: GetGridPoint: Invalid FieldGridStagger specified.");
        }
    }

    // Write the field data to an HDF5 file. This will overwrite the file if it already exists.
    void WriteHDF5(const std::string filename) const {
        const hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
        if (file_id < 0) {
            throw std::runtime_error("Failed to create HDF5 file: " + filename);
        }
        WriteHDF5(file_id);
        H5Fclose(file_id);
    }

    // Write the field data to an already open HDF5 file that you already have open.
    void WriteHDF5(const hid_t file_id) const {

        if (file_id < 0) {
            throw std::runtime_error("Invalid HDF5 file_id passed to WriteHDF5.");
        }
    
        // Copy the MultiFab to a single rank
        int dest_rank = 0; // We are copying to rank 0
        const std::shared_ptr<amrex::MultiFab> mf = CopyMultiFabToSingleRank(multifab, dest_rank);
    
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

            {
                // Add string attribute to this dataset for field_grid_stagger
                std::string stagger_str = FieldGridStaggerToString(field_grid_stagger);
                hid_t attr_type = H5Tcopy(H5T_C_S1);
                H5Tset_size(attr_type, stagger_str.size());
                hid_t attr_space = H5Screate(H5S_SCALAR);
                hid_t attr_id = H5Acreate2(dataset_id, "field_grid_stagger", attr_type, attr_space, H5P_DEFAULT, H5P_DEFAULT);
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

    // Helpful because it automatically generates all six relational operators (<, <=, >, >=, ==, !=) based on member-wise comparison.
    // But note that comparing the data member grid ( ...which is has a type shared_ptr<Grid> ) the operators compares the pointer addresses, not the contents of the Grid objects.
    // In general don't think it would make sense to compare two fields built on different grids with the less than or greater than operators (<, >). But doing so with pointer address does work to supply a strict weak ordering, even if it is an arbitrary one, which lets us store Field in a standard ordered containers like std::set or std::map.
    auto operator<=>(const Field& other) const = default;

    //-----------------------------------------------------------------------//
    // Public Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Grid> grid;
    const std::string name;
    const FieldGridStagger field_grid_stagger;
    std::shared_ptr<amrex::MultiFab> multifab;

private:

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//    

    amrex::IndexType FieldGridStaggerToAMReXIndexType(const FieldGridStagger field_location) const {
        switch (field_location) {
            case FieldGridStagger::Nodal:        return amrex::IndexType({AMREX_D_DECL(1,1,1)});
            case FieldGridStagger::CellCentered: return amrex::IndexType({AMREX_D_DECL(0,0,0)});
            case FieldGridStagger::IFace:        return amrex::IndexType({AMREX_D_DECL(1,0,0)});
            case FieldGridStagger::JFace:        return amrex::IndexType({AMREX_D_DECL(0,1,0)});
            case FieldGridStagger::KFace:        return amrex::IndexType({AMREX_D_DECL(0,0,1)});
            default:                          throw std::invalid_argument("Field:: Invalid FieldGridStagger specified.");
        }
    }

    std::shared_ptr<amrex::MultiFab> CopyMultiFabToSingleRank(const std::shared_ptr<amrex::MultiFab>& source_mf, int dest_rank) const {
        // Create a temporary MultiFab to hold all the data on a single rank
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

};



class FieldContainer {
public:

    //-----------------------------------------------------------------------//
    // Public Member Types
    //-----------------------------------------------------------------------//
    // Const iterator types for external iteration
    using const_iterator = std::set<std::shared_ptr<Field>>::const_iterator;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    FieldContainer(const std::shared_ptr<Grid>& grid);

    std::shared_ptr<Field> Insert(const std::string& name, const FieldGridStagger stagger, const std::size_t n_component, const std::size_t n_ghost);

    bool Contains(const std::string& name) const noexcept {
        for (const std::shared_ptr<Field>& field : fields_) {
            if (field->name == name) {
                return true;
            }
        }
        return false;
    }

    std::shared_ptr<Field> Get(const std::string& name) const;

    // Probably just going to get rid of this and just call the WriteHDF5 function on the fields directly in the application code since it is so simple to do with a range based for loop.
    void WriteHDF5(const hid_t file_id) const;

    // Const-only iteration support
    const_iterator begin() const { return fields_.begin(); }
    const_iterator end() const { return fields_.end(); }

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Grid> grid_;
    std::set<std::shared_ptr<Field>> fields_;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//    


};

} // namespace turbo
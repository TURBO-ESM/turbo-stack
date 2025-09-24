#pragma once

#include <cstddef>
#include <memory>
#include <string>
//#include <functional>
//#include <type_traits>
//#include <unordered_set>

#include <hdf5.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "grid.h"

namespace turbo {

enum class FieldLocation {
    Nodal,         
    CellCentered,  
    IFace,         
    JFace,         
    KFace          
};

class FieldContainer {

public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//
    using ValueType = amrex::Real;


    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    // Constructors
    FieldContainer(const std::shared_ptr<Grid>& grid);

    std::shared_ptr<amrex::MultiFab> AddField(const std::string& name, const FieldLocation stagger, const std::size_t n_component = 1, const std::size_t n_ghost = 0);

    void WriteHDF5(const hid_t file_id) const;

private:

    //-----------------------------------------------------------------------//
    // Private Data Members
    //-----------------------------------------------------------------------//
    const std::shared_ptr<Grid> grid_;
    std::map<std::string, std::shared_ptr<amrex::MultiFab>> name_to_multifab;

    //-----------------------------------------------------------------------//
    // Private Member Functions
    //-----------------------------------------------------------------------//    

    std::string FieldLocationToString(const FieldLocation field_location) const {
        switch (field_location) {
            case FieldLocation::Nodal:        return "Nodal";
            case FieldLocation::CellCentered: return "CellCentered";
            case FieldLocation::IFace:        return "IFace";
            case FieldLocation::JFace:        return "JFace";
            case FieldLocation::KFace:        return "KFace";
            default:                          throw std::invalid_argument("FieldContainer:: Invalid FieldLocation specified.");
        }
    }

    amrex::IndexType FieldLocationToAMReXIndexType(const FieldLocation field_location) const {
        switch (field_location) {
            case FieldLocation::Nodal:        return amrex::IndexType({AMREX_D_DECL(1,1,1)});
            case FieldLocation::CellCentered: return amrex::IndexType({AMREX_D_DECL(0,0,0)});
            case FieldLocation::IFace:        return amrex::IndexType({AMREX_D_DECL(1,0,0)});
            case FieldLocation::JFace:        return amrex::IndexType({AMREX_D_DECL(0,1,0)});
            case FieldLocation::KFace:        return amrex::IndexType({AMREX_D_DECL(0,0,1)});
            default:                          throw std::invalid_argument("FieldContainer:: Invalid FieldLocation specified.");
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

} // namespace turbo
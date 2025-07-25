#include <cstddef> // for std::size_t

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "tripolar_grid.h"

TripolarGrid::TripolarGrid(std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z)
    : n_cell_x_(n_cell_x), n_cell_y_(n_cell_y), n_cell_z_(n_cell_z)
{
    // Initialize the MultiFab with the specified number of cells


    // lower and upper indices of domain
    {
        const amrex::IntVect cell_low_index(0,0,0);
        const amrex::IntVect cell_high_index(n_cell_x - 1, n_cell_y - 1, n_cell_z - 1);
        amrex::Box cell_centered_box(cell_low_index, cell_high_index);

        amrex::BoxArray cell_box_array(cell_centered_box);
        const int max_chunk_size = 32; // Define a maximum chunk size for the BoxArray
        cell_box_array.maxSize(max_chunk_size);

        amrex::DistributionMapping distribution_mapping(cell_box_array);

        // number of components for each array
        int Ncomp = 1;

        // number of ghost cells
        int Nghost = 1;

        cell_center_scalar.define(cell_box_array, distribution_mapping, Ncomp, Nghost);
    }

}
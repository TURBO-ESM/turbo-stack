#pragma once

#include <cstddef> // for std::size_t

#include <AMReX.H>
#include <AMReX_MultiFab.H>

class TripolarGrid {

public:

    TripolarGrid(std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z);

    std::size_t NCell() const noexcept  { return n_cell_x_ * n_cell_y_ * n_cell_z_; }
    std::size_t NCellX() const noexcept { return n_cell_x_; }
    std::size_t NCellY() const noexcept { return n_cell_y_; }
    std::size_t NCellZ() const noexcept { return n_cell_z_; }

    amrex::MultiFab cell_scalar;
    amrex::MultiFab cell_vector;

    amrex::MultiFab x_face_scalar;
    amrex::MultiFab x_face_vector;

    amrex::MultiFab y_face_scalar;
    amrex::MultiFab y_face_vector;

    amrex::MultiFab z_face_scalar;
    amrex::MultiFab z_face_vector;

    amrex::MultiFab node_scalar;
    amrex::MultiFab node_vector;

private:

    // Number of cells in each direction
    const std::size_t n_cell_x_;
    const std::size_t n_cell_y_;
    const std::size_t n_cell_z_;
    
    // Domain dimensions... hardcoded for simplicity
    const double x_min_=0.0;
    const double y_min_=0.0;
    const double z_min_=0.0;

    const double x_max_=1.0;
    const double y_max_=1.0;
    const double z_max_=1.0;

    const double Lx_=x_max_-x_min_;
    const double Ly_=y_max_-y_min_;
    const double Lz_=z_max_-z_min_;

    // Grid spacing
    const double dx_=Lx_/n_cell_x_;
    const double dy_=Ly_/n_cell_y_;
    const double dz_=Lz_/n_cell_z_;


};
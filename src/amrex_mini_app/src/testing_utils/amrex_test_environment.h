#pragma once

#include <iostream>

#include <gtest/gtest.h>

#include <AMReX.H>

class AmrexEnvironment : public ::testing::Environment {
public:
    void SetUp() override {
        int argc = 1;
        char arg0[] = "test";
        char* argv_array[] = { arg0, nullptr };
        char** argv = argv_array;
        amrex::Initialize(argc, argv);
        std::cout << "AmrexEnvironment SetUp called\n";
    }
    void TearDown() override {
        amrex::Finalize();
        std::cout << "AmrexEnvironment TearDown called\n";
    }
};
